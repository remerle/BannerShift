# Pinned Notifications — Design

Date: 2026-05-25
Status: Approved (pending spec review)

## Summary

Add an always-on-top list window that captures matching notifications and keeps
them on screen after the underlying banner disappears, so important
notifications are not lost when their banner times out. Each pinned item can be
dismissed individually, or all at once with "Dismiss All". Clicking a row brings
the source app forward. Conceptually similar to the Microsoft Outlook
meeting-reminder window.

Pinning is an **additive action** on the existing rule model: a rule keeps its
position/animation behavior and may *also* pin matching banners to the list.

## Requirements (decided)

- **Action model:** additive flag on `Rule`. A matching banner is still
  repositioned per the rule; pinning is layered on top.
- **Persistence:** in-memory only for the running session. The list survives
  banners disappearing, but a quit/crash/reboot clears it. **No notification
  content is ever written to disk**, so the project's standing security rule
  ("never write notification body/title/subtitle to disk except in debug mode")
  is honored with no carve-out. Only the window frame origin is persisted (not
  notification content).
- **Window lifecycle:** visible only when non-empty. Appears on first pin, hides
  itself when the last item is dismissed.
- **Always-on-top:** the window floats above other apps' windows, follows the
  user across Spaces, shows over full-screen apps, and does not steal keyboard
  focus when interacted with.
- **De-duplication:** collapse by `(bundleID ?? lowercased appName, title)` into
  a single row with a count badge; newest body wins. Distinct titles are
  distinct rows.
- **Ordering:** newest group on top. Re-pinning an existing group bumps it back
  to the top.
- **Row interaction:** clicking a row activates the source app (via bundle ID
  through `NSWorkspace`). Per-row dismiss (×) and a "Dismiss All" footer.
- **Position:** draggable; the window frame origin is remembered across shows.
  Defaults to the top-right of the main screen on first-ever show.

## Architecture

Follows the existing Core / executable split. All pure logic (the list and its
collapse/dedup/cap semantics) lives in `BannerShiftCore` and is unit-tested. All
AppKit / AX / `NSWorkspace` integration lives in the executable target and is
verified manually against real notifications.

### Capture wiring (Approach A)

`BannerMover` already extracts `BannerText` and finds the matched `Rule` on each
pass. It gains one injected callback:

```swift
init(..., onPin: @escaping (CapturedNotification) -> Void = { _ in })
```

The mover's internal `ResolvedMatch` is extended to carry `pinsToList` plus the
captured fields. `onPin(...)` fires **exactly at the existing first-sight branch**
in `processWindow` (`if windowSnapshots[id] == nil { … }`).

Why first-sight: the mover re-processes the same on-screen banner across many
debounced AX passes. Firing capture only on first sight of a window id makes
capture **idempotent per banner** — a banner lingering across many passes is
captured once; a burst of distinct banners (each a fresh window id) is captured
per-banner. The count therefore reflects distinct banner arrivals, not debounce
passes.

The no-rules fast path is unaffected: `BannerMover` still skips AX text
extraction when there are no rules, since pinning only happens behind a matched
rule.

`AppDelegate` wires `onPin:` to `ReminderController.capture(_:)`. The mover runs
main-thread-only, so no thread hop is needed.

## Components

### Core: `Rule` (modified)

Add one field:

```swift
/// When true, a matching banner is also captured into the always-on-top
/// pinned-notifications list, in addition to any repositioning.
public var pinsToList: Bool   // defaults to false
```

Synthesized `Codable`, no custom decoder. Backward compatibility is **not** a
goal (nothing has shipped): a rule blob persisted before this field existed
fails to decode, and `RuleStore.load()` already starts empty on a decode
failure. New rules round-trip normally.

### Core: `Sources/BannerShiftCore/Reminders/` (new)

```swift
/// An immutable snapshot of one captured banner, as handed to the list.
/// Treat as sensitive: same notification content the matcher sees.
public struct CapturedNotification: Equatable, Sendable {
  public let appName: String
  public let bundleID: String?
  public let title: String
  public let body: String          // newest body wins on collapse
}

/// One row in the list: a collapsed group keyed by
/// (bundleID ?? lowercased appName, title), carrying an occurrence count
/// and a stable id for the UI.
public struct PinnedItem: Equatable, Sendable, Identifiable {
  public let id: String            // derived from the collapse key
  public let appName: String
  public let bundleID: String?
  public let title: String
  public let body: String          // latest
  public var count: Int            // >1 renders a badge
}

/// In-memory, ordered collection of pinned items with collapse-by-key
/// semantics. Pure value type — no AppKit, no persistence. The exec
/// target holds one as mutable state.
public struct PinnedList: Equatable {
  public private(set) var items: [PinnedItem]   // newest group first

  /// Capture one notification. If an item with the same collapse key
  /// exists, bump its count, replace body with the newest, and move the
  /// group to the top; otherwise insert a new row at the top. Enforces
  /// the row cap, evicting the oldest group when exceeded.
  public mutating func pin(_ n: CapturedNotification)

  public mutating func dismiss(id: String)
  public mutating func dismissAll()
  public var isEmpty: Bool { items.isEmpty }
}
```

Collapse key: `(bundleID ?? lowercased appName) + "\u{0}" + title`.

Row cap: `Constants.maxPinnedItems` (~50). When exceeded, the oldest group (at
the bottom) is dropped.

### Exec: `ReminderController` (new, `Sources/BannerShift/UI/`)

Owns the `PinnedList` mutable state and the panel window controller. Public
surface: `capture(_:)`, plus internal dismiss handlers wired to the UI.

- After any mutation, re-render. If `isEmpty`, order the window out; otherwise
  order it front **without activating**.
- First capture creates/shows the panel.

### Exec: the panel

`NSPanel`-based, with:

- `styleMask`: `.nonactivatingPanel`, `.titled` (no `.closable` — the only ways
  to clear are per-row × or Dismiss All).
- `level = .floating` (above normal app windows). `.statusBar`/`.screenSaver`
  levels are a deliberate non-goal for v1; revisit only if `.floating` proves
  insufficient.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- `isFloatingPanel = true`, `hidesOnDeactivate = false`.

Contents: a vertical `NSStackView` of row views driven by `PinnedList.items`
(the list is capped and small, so no `NSTableView`/diffable machinery — YAGNI).
Each row: app name + count badge (when >1), title, truncated body, dismiss (×)
button. Footer: "Dismiss All" button.

Interactions:

- Row click → activate source app via `NSWorkspace.shared.openApplication`,
  resolving a URL from `bundleID`. No-op if `bundleID` is nil/unresolved. No new
  entitlement required.
- × → `list.dismiss(id:)`.
- Dismiss All → `list.dismissAll()`.

Position: draggable; `windowDidMove` saves the frame origin to `Preferences`
(new key). On first-ever show with no saved frame, default to top-right of the
main screen's visible frame.

### Exec: `Preferences` (modified)

Add a key for the persisted window frame origin (e.g.
`pinnedListWindowOrigin`). Frame origin is not notification content; persisting
it is safe.

### Exec: `RuleEditSheetController` (modified)

Add a checkbox in the Action section: "Also pin to the always-on-top list",
bound to `Rule.pinsToList`. No other editor changes.

## Edge cases

- **Idempotency:** handled by first-sight capture (see wiring). Count reflects
  distinct banner arrivals.
- **Process teardown:** when `notificationcenterui` exits, `BannerMover.reset()`
  runs but **does not** touch the pinned list — pinned items deliberately
  outlive the banners. The list clears only on dismiss, Dismiss All, or app
  quit.
- **App resolution for activation:** reuse the bundle ID already resolved during
  matching; pass it through `CapturedNotification.bundleID` so a row click does
  not re-resolve.
- **Cap eviction:** oldest group dropped when the row cap is exceeded.

## Testing

Core, exhaustively (Swift Testing — `@Test`, `#expect`):

- `PinnedList.pin` collapse-by-key into one row.
- Count increments on repeat.
- Newest-on-top ordering; re-pin bumps an existing group to the top.
- Newest body wins on collapse.
- Distinct titles produce distinct rows.
- `dismiss(id:)` removes one row; `dismissAll()` empties.
- Cap eviction drops the oldest group.
- Collapse key falls back to `appName` when `bundleID` is nil and is
  case-insensitive on `appName`.

The panel and `NSWorkspace` activation are exec-target and verified manually
against real macOS notifications (consistent with the project's rule that the
executable target has no unit tests).

## Changelog

Not updated as part of this work. Nothing has shipped yet; the changelog is
populated at release time, not incrementally during v1 development.

## Security

The list is in-memory only; no notification content touches disk, so the "never
write notification content to disk outside debug mode" rule is honored unchanged.
Only the window frame origin is persisted. No new entitlements are introduced
(`NSWorkspace` app activation does not require one).
