# BannerShift — Functional Specification


## 1. Purpose

BannerShift is a macOS background utility that repositions the system's native notification banners to a user-chosen location on the screen.

The system normally posts every notification banner at a single, fixed location (the top-right corner of the active display). BannerShift lets the user pick any of nine positions arranged in a 3×3 grid (the four corners, the four edge midpoints, and the screen center) and ensures that every banner the operating system posts is repositioned to that location for as long as the banner remains visible.

The application is non-intrusive: it does not replace the notification system, does not render its own banners, and does not subclass or inject anything into other processes. To support user-defined per-notification rules (§22), it reads the *visible* text of each banner — app name, title, subtitle, body — at the moment the banner appears, and uses that text solely to choose a matching rule. Read text is held in memory for the lifetime of the banner and discarded. Banner content is never persisted except when the user has explicitly enabled debug logging (see §14).

## 2. Audience and Use Case

The target user is anyone who finds the fixed top-right position of macOS notifications inconvenient — for example, users with very large or multi-monitor displays, users with mirrored displays for presentations, users with accessibility needs, or users who simply prefer a different location.

The user installs the application once, grants it Accessibility permission, picks a position from a menu-bar menu, and forgets about it. The selected position persists across launches and reboots.

## 3. Operating Environment

- macOS, modern version (the current build targets macOS 26.4.1 and newer; the underlying technique works on older macOS but the exact accessibility identifiers used to detect banners have varied across releases).
- Runs as a per-user background agent. No Dock presence. No main application window — the optional "about" window described in §12 is a transient utility window and is the sole exception. The only persistent surface is an optional menu-bar icon.
- Single-process, single-user. No network access. No background daemon. No helper tools.
- Requires the user to grant Accessibility permission in System Settings. Without that permission the application cannot do its job and will not start.

## 4. High-Level Behavior

When launched, the application:

1. Verifies it has Accessibility permission, prompting the user if not. If permission is denied, the application terminates immediately rather than running in a degraded state. Because Accessibility permission is granted asynchronously in System Settings (after the app has already terminated), the user must relaunch the application to pick up a newly granted permission; the app does not poll for permission grant. This is a deliberate UX choice over the alternative of running in a polling/degraded mode.
2. Locates the operating system's notification UI process (a system-provided process that owns the windows in which notification banners are drawn) and attaches an Accessibility observer to it. The notification UI process's bundle identifier is held in a single source-level constant, alongside other macOS-version-fragile strings (see §9 and §20).
3. Registers for accessibility events that signal "a new window appeared," "the children of an existing window changed," and "a window was destroyed."
4. Reads the user's previously chosen position from persistent storage, defaulting to Top Middle if no choice has been saved (see §5 for the canonical position names).
5. Optionally installs a menu-bar status item that exposes the position picker and a few utility actions.
6. Begins listening. From this point forward, the application is event-driven: it does no polling and consumes essentially no CPU when no notifications are being shown.

When the operating system posts a notification banner, the accessibility observer fires. The application responds by:

1. Inspecting the window that contains the new banner.
2. Determining which physical display the window currently belongs to.
3. Computing a target position on that display for the user's chosen grid cell.
4. Asking the accessibility system to set the window's position to that target.
5. Remembering, for each window it has moved, the window's original position so that the move can be reversed cleanly if and when the application decides the window should go back where macOS originally put it.

When the user opens the full Notification Center panel (by clicking the clock, for example), the application detects this state and restores any previously moved window to its original position so that BannerShift does not fight the operating system over the placement of the Notification Center itself. Once the panel closes and a new banner appears, the move-on-appear behavior resumes.

When the notification UI process exits (which the operating system does occasionally, for example after sleep/wake), the application detects the termination, releases its observer, and reattaches a fresh observer the moment the process relaunches. This recovery is automatic and silent.

## 5. The Nine Positions

The position picker exposes exactly nine positions, arranged as a 3×3 grid:

| Vertical band | Left column | Center column | Right column |
| ------------- | ----------- | ------------- | ------------ |
| Top           | Top Left    | Top Middle    | Top Right    |
| Middle        | Middle Left | Middle (center of screen) | Middle Right |
| Bottom        | Bottom Left | Bottom Middle | Bottom Right |

Top Right corresponds (approximately) to the operating system's default position. The other eight positions are the value proposition of the application.

Each position has a stable internal identifier. The currently selected position is persisted in standard per-user preferences storage under a well-known key, as a string. On launch, the stored value is read; if it is missing or malformed, the application falls back to Top Middle.

## 6. How a Banner Is Found and Moved

The notification UI process owns one or more accessibility windows. When a banner is posted, the operating system creates an accessibility element somewhere inside one of those windows whose accessibility subrole is one of a known set of banner-style subroles (covering both transient "banner" notifications and persistent "alert" notifications). The application:

1. Walks the accessibility tree of each notification UI window depth-first, looking for the first element whose subrole matches any in the known banner-subrole set.
2. Captures the banner's visible text by walking the matched banner's subtree and reading string values from each text-bearing child (typically `AXStaticText` elements for app name, title, subtitle, body). The captured text is fed to the rule matcher (§22) and is not persisted.
3. Reads that banner element's position and size, and the window's position and size, all in accessibility coordinates (top-left origin).
4. Identifies the display the window belongs to by computing the AppKit coordinate of the window's center point (which requires flipping the y-axis using the height of the primary display, not the union of all displays) and finding the first display whose AppKit frame contains that point. If no display matches, the application falls back, in order, to: (a) the screen reported by `NSScreen.main` at the moment of computation (which, for a background agent with no key window, is the screen most recently containing an active window — the OS-defined "active" screen), and (b) the primary display (the screen at index 0 of `NSScreen.screens`, i.e., the one containing the menu bar).
5. Consults the rule matcher (§22) using the captured banner text. The matcher returns the rule that wins (or no rule), which determines the target position (rule override, or the global default from §5) and animation (rule override, or the global default of `none`).
6. Decides what the window's origin must be set to in order for the banner element inside it to appear at the chosen grid cell on the chosen display. The math is described in the next section.
7. Sets the window's position attribute via the accessibility API, possibly via an animator (§22) that issues a sequence of position writes over time rather than a single set.

The application never touches the banner element directly. It only moves the *window* that contains the banner. This is important because the banner is laid out relative to its container window, and moving the window is the only stable lever the accessibility API exposes.

## 7. Position Math

The notification UI window is, in practice, the size of the entire display: it spans from the top of the display to the bottom, and from the left edge to the right edge. The banner element lives inside that window in the upper-right region, with a small right-edge padding.

Because the container window is full-screen-sized, repositioning the *window* shifts the *banner inside it* by the same delta. To make the banner appear at the chosen grid cell on the chosen display, the application solves for the window origin such that the banner's final on-screen rectangle lands at the desired location.

The calculation uses:

- The window's current frame (origin and size).
- The banner's current frame (origin and size), relative to that window.
- The chosen display's full frame (`screenFrame`).
- The chosen display's visible frame (`visibleFrame`) — i.e., the area not covered by the menu bar or Dock. The difference between these two heights is treated as "Dock size" for purposes of avoiding the Dock.
- A small constant padding (currently 30 points) used to keep middle- and bottom-row positions clear of the Dock. This constant lives in a single named source-level constant and is not user-tunable; it is a value derived from observation of the OS-default banner layout.
- A small right-edge banner padding (currently 16 points) corresponding to the operating system's own inset of the banner from the right edge of its container. Same constraint: single named source-level constant, not user-tunable.

The horizontal axis is computed as follows:

- Left column: the window is shifted left so that the banner's left edge lines up with the screen's left edge (accounting for the banner's offset from its container's right edge).
- Center column: the window is shifted so that the banner is horizontally centered on the chosen display.
- Right column: the window stays in its natural horizontal position, which already places the banner near the right edge — matching the OS default.

The vertical axis is computed as follows:

- Top row: no vertical shift; the banner sits where the OS originally drew it.
- Middle row: the window is shifted upward so the banner ends up vertically centered on the visible portion of the display, with the Dock-padding constant applied so that on bottom-Dock setups the banner does not collide with the Dock.
- Bottom row: the window is shifted upward so the banner sits just above the bottom of the visible area, again with Dock-padding applied.

The final target origin is snapped to integer points. The operating system clamps non-integer window positions to integers anyway, so submitting non-integer values would result in unpredictable truncation.

The math depends on one un-documented invariant: that the notification UI container window's height equals the display's height. This has held from macOS 12 through 26 but is not contractually guaranteed; the application should assert this invariant at runtime so a future regression is loud rather than silent.

## 7.1 Image Fidelity

Because the application moves a window every time a banner appears (and, with animations, repeatedly during a single banner's lifetime), it must avoid introducing visual blur or sub-pixel rendering artifacts. The known failure modes and the application's mitigations:

1. **Non-integer point coordinates.** macOS renders crisp text and vector content only when the window's origin is an integer point. Even on a 2× Retina display, the origin must be integer in points (the OS handles the device-pixel-grid alignment internally). Mitigation: every target origin emitted by the position calculator (§7) and every intermediate point emitted by the animator (§22) is rounded to integers before being passed to the accessibility position attribute. This is enforced by tests that sweep across positions and animation styles and assert integer-only output.

2. **Writes during the OS's own banner-entry animation.** When the operating system first posts a banner, it animates the window into view from the right edge of the display over roughly 150 ms. If the application sets the position while that animation is in flight, the operating system may briefly interpolate between *its* intended end position and the application's, producing a one- or two-frame visual tear (not persistent blur, but visible). The application accepts this tear for the initial move because the alternative — delaying the move 150 ms — produces a visible "banner appears at the OS location, then jumps" effect that is worse. For user-opted-in animations (§22 — slide, shake, bounce), the animator waits 150 ms after the initial snap before starting, so animation frames never overlap the OS's own entry animation.

3. **Sub-pixel jitter during animation.** Same root cause as (1); same mitigation. Every animation frame's point is rounded before emit. Tested.

4. **Backing-scale mismatch when crossing displays.** Banners normally stay on the display where the OS originally posted them, and the application's display selection (§6) reflects that. If a user physically drags the banner-owning display between attached monitors mid-banner, the window's backing surface may briefly render at the wrong scale until macOS refreshes it. Not currently mitigated; considered acceptable.

5. **Repeated writes amplifying any of the above.** The debouncer (§10) collapses event bursts so the application never issues more than one move per ~30 ms quiet window per banner. The animator (§22) limits per-banner animation writes to ≤20.

Verification:

- Automated: tests in the position calculator and animation-frames modules assert integer-only output across a sweep of inputs.
- Manual: the smoke test (§22's re-implementation checklist item 5 / the manual integration test) includes a fidelity check — observe a real banner under each animation style and visually confirm the text is crisp.

## 8. The "Baseline" Concept

Once the application has moved a banner window, subsequent accessibility events on that same window will report the *moved* position and frame, not the OS's original layout. If the application were to recompute the target from the post-move frame, it would drift on every event.

To prevent this, the application captures, on the first move of a given window, a "baseline":

- The window's original origin (the position the OS chose).
- The window's full frame at the time of the first move.
- The banner's full frame at the time of the first move.

All subsequent target-origin calculations for that window use the baseline frames, not the live frames. The baseline is held in a single record so that its three fields can only ever be set or cleared as a unit.

The identity of a moved window is its accessibility-element pointer identity, not any combination of its attributes. Two banners with identical sizes would defeat any attribute-based identity check, and the operating system may reorder windows under the application, so only pointer identity is stable.

When the window's banner disappears (no banner element is found inside it), or when the full Notification Center panel opens, the application restores the window to the baseline origin and clears the baseline. Restoration is gated on pointer equality with the originally moved window, so it can never move the wrong window.

## 9. The Notification Center Panel

When the user opens the full Notification Center panel (typically by clicking the clock in the menu bar), that panel is drawn inside the same notification UI process and surfaces as the same kind of accessibility window — but it is not a banner and should not be repositioned.

The application distinguishes a banner from an open Notification Center panel by searching the window's accessibility tree for a specific well-known accessibility identifier that is present only on a control inside the panel (currently the "widget editor" button). When that identifier is present, the application treats the window as the open panel: it restores any previously applied move on that window and does nothing else for the duration of the panel's lifetime.

This identifier is a known fragile dependency. Apple has changed it across major macOS releases. The identifier string lives in one well-known constant so it can be updated quickly when it breaks.

## 10. Event Handling and Debouncing

The accessibility events that signal "a banner appeared" come in bursts. A single notification can produce many events in rapid succession: the window is created, the window's children change, children of children change, and so on. Each event is a synchronous round trip into the notification UI process via the accessibility API. Handling each event independently would produce dozens of redundant moves and noticeable CPU spikes.

The application coalesces these bursts using a short debounce (currently 30 milliseconds). When an event fires, the application:

1. Refreshes its set of observed windows (so newly created windows start producing events).
2. Cancels any pending debounced move.
3. Schedules a fresh move pass to run 30 milliseconds in the future on the main run loop.

The debounced move pass iterates over every notification UI window and applies the move-or-restore logic described above. If another event arrives during the 30 ms window, the pending pass is replaced rather than augmented.

The debounce interval is small enough to be imperceptible to the user (the move happens essentially as the banner appears) but large enough to collapse a typical event burst into a single pass.

## 11. Notification UI Lifecycle

The operating system's notification UI process is not guaranteed to be alive for the entire lifetime of BannerShift. macOS terminates and relaunches it under a variety of conditions (sleep/wake, logout/login, OS updates, crashes). When the process is not running, there are no banners to move; when it relaunches, BannerShift must reattach.

The application registers two workspace-level observers:

- One for "an application terminated." When the terminated application's bundle identifier matches the notification UI process, the application releases its accessibility observer and clears all tracked state (observed window keys, moved-window record).
- One for "an application launched." When the launched application's bundle identifier matches the notification UI process, the application performs a fresh observer setup — creating a new accessibility observer, attaching it to the new process, and registering for the standard set of notifications.

Reattachment must be idempotent and must not double-register observers if it is somehow triggered twice. The observer dedup set is keyed by a deterministic tuple of role, subrole, size, and the accessibility-element pointer identity of the observed window so that re-registration of the same window does not produce duplicate registrations. Element identity is included because role+subrole+size alone collides when two stacked banners happen to share dimensions; pointer identity is stable within a window's lifetime (§8) and disambiguates the case. Crucially, the dedup key does *not* include the window's position, because position changes every time the application moves a window. If position were included, the same physical window would generate a new key on every move and the observer set would grow unboundedly.

## 12. Menu Bar Surface

When the menu-bar icon is enabled, the status item displays a small template (monochrome, system-tinted) icon. Clicking it opens a menu containing, in order:

1. A "Rules…" menu item that opens the rule editor (see §22).
2. A separator.
3. The nine grid positions, each as its own menu item. The currently selected position is shown with a checkmark; selecting a different one updates the persisted preference and immediately reapplies the move logic so any currently visible banner snaps to the new location.
4. A separator.
5. A "send a test notification" action that posts a real notification through the standard user notification framework so the user can verify the move is working. The test notification's title is the application name; its subtitle is the currently selected position's display name; its body is a short fixed string. If permission to post user notifications has not yet been granted, the application requests it; if the user denies, the application shows an explanatory error and instructs the user how to enable notifications in System Settings.
6. A separator.
7. A "launch at login" toggle. This uses the modern login-item service and reflects three possible states: not registered, enabled, and "requires approval" (the last state arises when the system has not yet approved the registration, which happens on some systems). The menu item title and check state change to reflect the live status, which is re-read every time the menu is opened. If a toggle results in "requires approval," the application offers to open the relevant System Settings pane.
8. A "hide menu bar icon" action that, after confirming with the user, removes the status item. The hidden state is persisted. The user is told (in the confirmation dialog) that relaunching the application will reveal the icon again — this works because the application listens for its own "became active" event and, if the icon is hidden, treats activation as a request to show it again and reset the preference.
9. A separator.
10. An "about" action that opens a small fixed-size, untitled-style window showing the application icon, name, version (from the bundle), maintainer line, and copyright (from the bundle). The window is non-resizable, closable, and disposed-of by hiding rather than destroying so re-opening is instantaneous.
11. A "quit" action.

The menu-bar icon's visibility is independent of the application's running state: hiding the icon does not stop the application, and the application can run perfectly well headless. This is intentional, because some users will set up BannerShift once and never want to see it again.

## 13. Persistence

Four pieces of state are persisted, each as a single key in standard per-user preferences storage:

- The default position (string identifier, one of the nine).
- Whether the menu-bar icon is hidden (boolean).
- Whether debug logging is enabled (boolean).
- The user's rule list — a single `Data` value containing a JSON-encoded array of rule records (see §22).

The first three keys are typed scalars; the fourth is JSON because rules have variable structure (multiple optional regex patterns per rule). The keys are otherwise independent. Default values are: position = Top Middle, icon hidden = false, debug logging = false, rules = empty array. A malformed rules value at launch is logged and treated as an empty list — one corrupt rule never disables the rest of the application.

## 14. Logging

The application logs through two channels:

- The unified system logger, under a subsystem identifier matching the application's bundle identifier and a category of "app." Messages are tagged as info, debug, or error. Strings are emitted with public privacy because the application does not log notification content.
- A plain-text log file under the user's `Library/Logs` directory, named after the application. The log file is created on first launch with restrictive permissions (owner read/write only, 0600), because debug entries can include notification titles when debug logging is explicitly turned on. The file is opened once at launch and held open as an append handle for the lifetime of the process, avoiding per-write open/seek/close churn. Each line is prefixed with a level tag and an ISO-8601 timestamp.

Info and error messages are always written. Debug messages are written only when the debug-logging preference is enabled; this preference is read live on each call rather than cached, so the user can flip the flag in preferences storage and have it take effect without relaunching.

## 15. Concurrency Model

The application runs entirely on the main run loop. The accessibility observer's run-loop source is added to the current run loop in default mode. All event handling, all preference updates, all menu actions, all window moves, and all menu-bar UI updates happen on the main thread.

The only asynchrony is:

- The 30 ms debounce timer, which schedules its work on the main queue.
- The notification framework's permission and post callbacks, which can fire on background queues and are explicitly bounced back to the main queue before showing any UI.

There is no shared mutable state across threads, so no locking is required.

## 16. Permissions

The application requires two permissions from the user:

- **Accessibility.** Mandatory. Without it, the application cannot observe the notification UI process or set window positions. On first launch the application prompts for it via the standard "request and prompt" accessibility API. If permission is denied, the application terminates immediately. The application advertises a usage-description string in its bundle metadata explaining why it needs accessibility.
- **User notifications.** Optional. Only required if the user wants to use the built-in "send a test notification" menu action. The application requests this permission lazily, only when the test action is invoked. Denial does not affect any other behavior.

No other permissions are requested. No file access outside the user's `Library/Logs` directory. No network. No microphone, camera, location, contacts, calendar, or full-disk access.

## 17. Sandbox and Code Signing

The application carries an entitlement file used solely to explicitly opt out of Apple-events automation (`com.apple.security.automation.apple-events = false`). There is no code-signing entitlement for accessibility — that permission is granted by the user at runtime in System Settings → Privacy & Security → Accessibility (TCC), and is checked via `AXIsProcessTrustedWithOptions`. The application is not sandboxed in the App Sandbox sense, because the accessibility API is not available to sandboxed apps. It is, however, distributable through the Developer ID program: the release build is signed with a Developer ID Application identity, hardened-runtime is enabled, and the resulting bundle is submitted to Apple's notarization service and stapled.

For development, a non-notarized ad-hoc-signed build is used; this build will not pass Gatekeeper and is intended only for the developer's own machine.

## 18. Build and Release

There are two distinct builds:

- **Development build.** A single `swiftc` invocation (or equivalent) that produces a universal binary (Intel + Apple Silicon), signed ad-hoc with a local identity, with no notarization. Used for fast iteration.
- **Release build.** Driven by a shell script that performs, in order: clean, compile, sign with the Developer ID Application identity (with hardened runtime and the application's entitlements), notarize via the App Store Connect API, staple the notarization ticket, and package the result into a tarball alongside the `.app` directory.

Secrets needed by the release build (the App Store Connect API key file, the API key ID, the issuer ID, and the Developer ID identity string) are materialized from a password manager via a helper script. None of these secrets live in the repository.

The bundle ID is `com.emerle.BannerShift` and is referenced both in `Info.plist` and in a single source-level constant; these must be kept in sync.

## 19. Versioning

Two adjacent keys in the bundle's `Info.plist` carry the application's version: a short, user-facing version string and a build number. Both are bumped together before each release build. The "about" window reads the short version string at runtime.

## 20. Constraints and Known Fragilities

The application depends on several behaviors of the operating system that are real and stable but not documented. These should be flagged so that a re-implementation knows what to watch for:

1. **The set of banner subroles.** The accessibility subroles used by the notification UI to mark banner-style elements change occasionally across major macOS releases. The application keeps these in a single constant set; updating that set is the most common form of maintenance.
2. **The "widget editor" identifier.** Used to detect that the full Notification Center panel is open. This is the most fragile single string in the application.
3. **The full-screen container window invariant.** All vertical position math relies on the notification UI's container window being the height of the display. This has held since macOS 12; if a future release ever ships a compact container, every middle-row and bottom-row computation breaks. The application should assert this invariant at runtime.
4. **The primary-display y-flip anchor.** Accessibility uses top-left-origin coordinates; AppKit uses bottom-left-origin. The correct y-flip pivot for display detection is the primary display's height, not the global maximum y across all displays. The latter looks superficially correct but breaks on multi-monitor setups where a secondary display is positioned physically above the primary.
5. **Window-identity stability.** The accessibility-element pointer for a given notification UI window is stable across position changes within its lifetime, but is *not* stable across notification UI process restarts. All window-keyed state must be cleared on observer teardown.
6. **Burst events.** Accessibility events arrive in bursts; without debouncing the application would do dozens of redundant moves per notification.

## 21. Out of Scope

The following are explicitly not part of the application and should not be added without a deliberate decision:

- Custom notification appearance (theming, fonts, colors, layouts).
- Custom notification content (replacing or augmenting what the OS shows).
- Replacement of the notification UI process.
- A general window manager. The application moves only the notification UI's banner windows, not arbitrary windows.
- Any cloud sync, telemetry, crash reporting, update checking, or analytics.
- Any background service or daemon component. The application is a single per-user GUI process.

## 22. Rules and Animations

### Why

By default every banner gets the user's global position from §5 with no animation. For users who want different treatment for different notifications (Slack DMs middle-screen with a shake, build failures top-left with a slide-in, calendar reminders top-right with no animation), the application supports a user-defined ordered list of rules. A rule matches a banner against its visible text and, on match, overrides the position and/or animation for that banner. If no rule matches, the global defaults apply.

### Banner Text Capture

When the application discovers a banner (§6), it walks the banner's subtree and captures four strings in addition to the banner's frame:

- App name (rendered next to the banner's app icon)
- Title
- Subtitle (if present)
- Body (if present)

A missing field is captured as an empty string. The captured strings are held in memory for the lifetime of the banner and discarded when the banner disappears. They are never written to disk except in debug logs (§14), which the user explicitly opts into.

The application additionally performs a best-effort resolution of the banner to a bundle identifier by matching the captured app-name string against the localized names of currently running applications (`NSWorkspace.shared.runningApplications`). Resolution fails silently for background daemons that post notifications without appearing in `runningApplications`; rules that do not use the bundle identifier are unaffected.

### Rule Structure

Each rule has:

- A unique identifier (UUID string).
- A user-supplied display name (free text; for UI labeling).
- An enabled flag.
- Up to five optional regex patterns: app name, bundle identifier, title, subtitle, body. Patterns are Swift `Regex` source strings. A missing pattern is a wildcard for that field.
- An optional position override (one of the nine grid positions, or `nil` to keep the global default).
- An optional animation choice (`none`, `slide`, `shake`, `bounce`; `nil` to keep the global default).

Rules are an ordered list; the first rule whose patterns *all* match (or are unset) is applied. A rule with all patterns unset is a valid catchall, useful as a final fallback.

Regex evaluation uses Swift's `Regex` type with case-insensitive matching and `.dotMatchesNewlines`. A malformed pattern is reported to the user in the rule editor (see below) and the containing rule is treated as disabled at runtime; the matcher never silently ignores a broken rule.

### Animations

Four animation styles, available both as per-rule overrides and as the global default (which itself defaults to `none`):

- **`none`** — banner snaps to the target position. This is the §7 behavior.
- **`slide`** — banner starts at its OS-default position and is animated to the target over ~200 ms with an ease-out curve. Useful for visually leading the user's eye to a non-default location.
- **`shake`** — banner is placed at the target, then oscillated by ±10 points on the x-axis at ~60 fps for 250 ms before settling. Useful for "urgent" rules.
- **`bounce`** — banner is placed at the target, then oscillated by ±10 points on the y-axis at ~60 fps for 250 ms.

Animations are driven by repeated AX position writes via `AXUIElementSetAttributeValue`. The animator starts ~150 ms after the initial position is set so that the OS's own banner-entry animation has finished. The animator cancels cleanly if the banner disappears mid-animation or if a new debounced pass produces a different target for the same window. Animation cost is small (≤20 cross-process writes per banner) but non-zero; the global default is `none` so BannerShift remains visually quiet for users who have not opted in.

### Rule Editor

The "Rules…" menu item (placed above the position picker in the menu bar — §12) opens a single utility-styled window:

- A table view on the left lists existing rules in evaluation order, showing: enabled toggle, display name, app match (or "(any)"), position+animation summary. Drag to reorder. Selecting a row populates the detail pane.
- "Add" and "Remove" buttons below the table.
- A detail pane on the right shows the selected rule: name, enabled toggle, five regex inputs (each with live validation — a red border and an inline error appear under any malformed pattern), position dropdown (nine positions or "(default)"), animation dropdown (four styles or "(default)").
- A "Test against sample text" field at the bottom of the window lets the user paste sample banner text (app, title, subtitle, body) and see which rule wins, or that nothing matches. This is the debugging path for non-trivial rule sets.
- Edits are saved immediately on focus change or table-selection change — there is no "Save" button and no in-window undo.

The window is fixed-size, non-resizable, closable. Re-opening is instantaneous: the window is hidden on close, not destroyed.

### Default Behavior

If the rule list is empty (the default on first launch), the application behaves exactly as described in §1–§21 of this spec: every banner gets the global position from §5 with the global animation of `none`. The rules feature adds no behavior to a user who hasn't created any rules.

### Persistence

The rule list lives in standard per-user preferences storage under the key `rules`, as a JSON-encoded `Data` value. Schema:

```json
[
  {
    "id":               "UUID string",
    "name":             "free-text display name",
    "enabled":          true,
    "appPattern":       "regex string or null",
    "bundleIDPattern":  "regex string or null",
    "titlePattern":     "regex string or null",
    "subtitlePattern":  "regex string or null",
    "bodyPattern":      "regex string or null",
    "position":         "top-left | top-middle | … | bottom-right | null",
    "animation":        "none | slide | shake | bounce | null"
  }
]
```

Decoding is forward-compatible: unknown fields in a persisted rule are silently ignored. Malformed rules at launch (corrupt JSON, unknown enum values) cause the application to log an error and start with the rule list empty — a single corrupt rule never disables the rest of the application.

## 23. Re-Implementation Checklist

If re-implementing from scratch, the minimum viable application must:

1. Launch as a background GUI agent, with no Dock icon and no main window.
2. Request and require accessibility permission.
3. Locate the notification UI process and attach an accessibility observer to it.
4. Register for window-created, children-changed, and window-destroyed accessibility events on both the application element and each of its windows.
5. On each event, find any banner element by subrole, capture a baseline frame the first time it is seen, capture the banner's visible text (app name, title, subtitle, body), consult the rule matcher (§22), compute a target window origin for the chosen 3×3 cell on the correct display, snap it to integer points, and apply it via the accessibility position attribute — possibly via an animator if the matched rule (or global default) requires animation.
6. Detect the open Notification Center panel by accessibility identifier and refrain from moving the window in that state, restoring any earlier move.
7. Debounce burst events.
8. Recover automatically when the notification UI process terminates and relaunches.
9. Persist the default position, the icon-visibility preference, the debug-logging preference, and the rule list.
10. Expose a menu-bar item with: a rule-editor entry, the position picker, test-notification action, launch-at-login toggle, hide-icon action, about, quit.
11. Provide a rule-editor window with table, add/remove, per-rule regex inputs with live validation, position/animation overrides, and a sample-text match tester.
12. Log info/error to the unified logger and a permission-restricted file; log debug only when explicitly enabled.
13. Ship as a Developer-ID-signed, notarized, stapled application targeting the same macOS version range.

Anything beyond this list is enhancement, not core functionality.
