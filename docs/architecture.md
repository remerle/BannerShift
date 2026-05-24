# Architecture

This document explains how BannerShift is structured internally and how a
notification banner travels from "the OS just posted it" to "it's sitting where
you asked." It's aimed at contributors. For the build/test workflow see
[DEVELOPERS.md](../DEVELOPERS.md); for user-visible settings see
[configuration.md](configuration.md).

## The two-target split

The code is split into two SwiftPM targets, and the split is load-bearing.

- **`BannerShiftCore`** (`Sources/BannerShiftCore/`) — a library of pure value
  types and pure logic: coordinate math, rule matching, animation frame
  schedules, the preferences/rules data model, debouncing. It imports no system
  UI frameworks (`AppKit`, `ApplicationServices`, `Cocoa`). Everything here is
  unit-tested in `Tests/BannerShiftCoreTests/`.
- **`BannerShift`** (`Sources/BannerShift/`) — the executable. It owns all
  AppKit and Accessibility (AX) integration: the app delegate, the AX observer,
  the menu-bar UI, the window mover. It is verified by exercising real macOS
  notifications against a built `.app`, not by unit tests.

The rule of thumb: **if a piece of logic could be tested without a Mac's window
server, it belongs in Core.** When something in the executable target starts to
look generally useful and has no UI/AX dependency, move it down into Core and
test it there.

## End-to-end flow

When a banner appears, control flows through these types in order. Everything
below runs on the **main thread** (see [Threading](#threading)).

```mermaid
flowchart TD
    A[notificationcenterui launches] --> B[NotificationUIWatcher]
    B -->|pid| C[AXObserverController]
    C -->|AX event| D[Debouncer<br/>30 ms coalesce]
    D --> E[BannerMover.process]
    E --> F[AXBannerFinder<br/>locate banner element]
    F --> G[BannerTextExtractor<br/>title / subtitle / body]
    G --> H[AppResolver<br/>app name to bundle ID]
    H --> I[RuleMatcher<br/>first matching rule]
    I --> J[PositionCalculator<br/>target screen origin]
    J --> K[Animator<br/>none / slide / shake / bounce]
    K --> L[AX position write]
```

1. **`NotificationUIWatcher`** observes `NSWorkspace` launch/terminate
   notifications for the system notification UI process
   (`com.apple.notificationcenterui`). When it launches, the watcher hands the
   pid to the app delegate, which brings up an observer. This indirection
   matters because `notificationcenterui` can crash and relaunch; the watcher
   re-attaches when it does.

2. **`AXObserverController`** owns an `AXObserver` for that pid. It registers for
   `kAXWindowCreated`, `kAXCreated`, `kAXUIElementDestroyed`, and
   `kAXLayoutChanged` on the app element and every existing window, and attaches
   the observer's run-loop source to the main run loop. A C trampoline routes
   each AX callback back into Swift. `refreshWindows()` picks up windows created
   after startup and prunes keys for windows that have gone away (so AX pointer
   reuse can't cause a new window to silently miss its notifications).

3. **`Debouncer`** (Core) coalesces event storms. AX can fire many callbacks for
   a single banner; the debouncer waits for `Constants.eventDebounceInterval`
   (30 ms) of quiet on the main queue before running one reposition pass. This
   keeps burst conditions from causing visible flicker or wasted work.

4. **`BannerMover`** runs the pass. For each top-level window of the
   notification UI process it:
   - skips the window if it's the *expanded Notification Center panel* rather
     than a transient banner (via **`NotificationCenterPanelDetector`**, which
     keys off `Constants.notificationCenterPanelIdentifier`), restoring any
     prior move first;
   - finds the banner element with **`AXBannerFinder`** (a depth-limited
     depth-first search for an AX subrole in `Constants.bannerSubroles`);
   - extracts text with **`BannerTextExtractor`** (recursively collects text
     elements, sorts them top-to-bottom, and assigns them to title / subtitle /
     body by a count heuristic);
   - resolves the source app's bundle ID with **`AppResolver`** (a cached
     name → bundle-ID lookup maintained from `NSWorkspace` launch/terminate
     notifications, so it doesn't scan every running app on each banner);
   - asks **`RuleMatcher`** (Core) for the first enabled rule whose patterns all
     match (case-insensitive `Regex`, AND across fields); the rule's position
     and animation override the global defaults, otherwise the default position
     and `none` apply;
   - computes the destination with **`PositionCalculator`** (Core) on the screen
     the banner currently belongs to (chosen by **`DisplaySelector`**), caching a
     **`BannerWindowSnapshot`** of the window's original geometry on first move;
   - dispatches the move through **`Animator`**.

5. **`Animator`** writes the AX position attribute. `none` snaps to the target;
   `slide` interpolates from the original origin to the target; `shake`/`bounce`
   snap to target then oscillate. Frame schedules are precomputed by
   `AnimationFrames` (Core) and dispatched as `DispatchWorkItem`s on the main
   queue at precomputed deadlines — nothing is allocated per frame. When a banner
   disappears, `BannerMover` restores the window's original position and drops
   its snapshot.

## Key Core types

| Type | Responsibility |
| --- | --- |
| `Position` | The nine grid positions and their string encodings. |
| `Animation` | The four animation styles. |
| `PositionCalculator` | Given screen geometry and a target position, computes the window origin; also holds the full-screen-container invariant check. |
| `AnimationFrames` | Precomputed frame schedules (offsets + integer-snapped points) per style. |
| `RuleMatcher` | Compiles rule patterns once and evaluates them against extracted banner text. |
| `Rule` / `RuleStore` | The rule data model and its persistence. |
| `Preferences` | Typed accessors over `UserDefaults`. |
| `Debouncer` | Main-queue event coalescing. |
| `FileLogger` | Leveled file logging with a size cap; debug level gated at write time. |
| `Constants` | The single source of truth for OS-dependent magic strings and numbers. |

## Threading

The AX API is synchronous and main-thread-bound. BannerShift leans into that:
the observer's run-loop source is attached to the **main** run loop, every AX
read/write happens on the **main thread**, and the debouncer schedules its pass
on the main queue. Do not introduce `async`/`await` at AX call sites — it would
obscure the threading invariant without buying anything, since the work must run
on main anyway. The only background work is `FileLogger`'s serial write queue.

## OS fragility

BannerShift depends on a handful of undocumented macOS internals. Each is
isolated to a constant in `Sources/BannerShiftCore/Constants.swift` so that when
a macOS major release breaks one, you fix the constant first and then the
dependent logic. When you add a workaround for a new OS version, note the symptom
and the macOS version in a comment on the affected constant.

| Constant | Value | What it identifies |
| --- | --- | --- |
| `notificationUIBundleIdentifier` | `com.apple.notificationcenterui` | The system process that hosts banners. |
| `bannerSubroles` | `AXNotificationCenterBanner`, `AXNotificationCenterAlert`, `AXSystemDialog` | AX subroles that mark a window's banner element. |
| `notificationCenterPanelIdentifier` | `widget-editor` | Present only when Notification Center is expanded; used to avoid moving the panel. |
| `dockPadding` | `30.0` pt | Keeps middle/bottom banners clear of the Dock. |
| `eventDebounceInterval` | `0.030` s | AX-event coalescing window. |
| `axErrorNotificationAlreadyRegistered` | `-25200` | Benign "already registered" AX error the Swift overlay doesn't name. |
| `maxAXRecursionDepth` | `32` | Depth cap when walking the (untrusted) AX subtree. |
| `maxBannerMatchSubjectLength` | `4096` | Caps regex input length to bound backtracking. |

There's also a structural invariant — the full-screen container window that
banners live inside — checked by `PositionCalculator.invariantHolds`. If it stops
holding, `BannerMover` bails out of repositioning that window rather than moving
something it doesn't understand.
