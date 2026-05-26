# Pinned Notifications — Redesign (v2)

Date: 2026-05-26
Status: Approved (pending spec review)
Supersedes: portions of [2026-05-25-pinned-notifications-design.md](2026-05-25-pinned-notifications-design.md) (capture wiring is unchanged; this redesigns the visible panel and the data model that backs it)

## Summary

Replace the current pinned-notifications panel with a fixed-column grid of
rows, one row per captured notification (no grouping). Add a relative-time
column. Make a row clickable to expand it in place, showing the wrapped full
body and an `Open <App> →` link. Ensure no row ever displays the macOS-26
SwiftUI fallback text (e.g. `"BannerShift, BannerShift, Bottom Left, …"`)
that the current AX extractor produces when banner text collapses into a
single accessibility node.

The previous design coalesced repeated notifications by
`(bundleID, title)` and showed a stacked-text row. In practice the stacking
made rows visually inconsistent and the collapse merged useful entries; the
new design treats each captured notification as its own row and aligns
every row on the same column boundaries.

## Goals

- One captured notification → one row. No grouping, no count badge.
- Strict column alignment. Every row uses the same fixed widths; only the
  body column flexes with the panel.
- Relative time per row, auto-refreshed once a minute.
- Click-to-expand drawer with the full wrapped body and an `Open <App>`
  link; collapses again on click.
- Garbage-free: a malformed `CapturedNotification` is never displayed.
- Capture wiring (`BannerMover` → `ReminderController.capture`) and the
  always-on-top panel behavior (non-activating `NSPanel`, persisted origin)
  carry over from the v1 design and are not redesigned here.

## Non-goals (deferred)

- Per-row screenshot capture of the original banner. Discussed and dropped:
  no clickable actions survive the original banner window's destruction,
  the storage and privacy surface aren't justified for v1.
- URL scraping of body text with `NSDataDetector` for an `Open Link →`
  affordance. Discussed and dropped: most banners don't include the URL in
  the body, and the partial coverage is worse than a consistent
  `Open <App>` behavior.
- Persisting expanded state across launches. All rows start collapsed on
  app launch.
- Per-row drag-to-reorder. Order is timestamp-newest-first.
- Group dismissal by source app.

## Panel and row layout

`NSPanel`, non-activating, always-on-top, follows the user across Spaces,
shows above full-screen apps, never steals keyboard focus. Existing
behavior; no changes here.

- **Minimum width: 600pt.** Users can drag wider; only the body column
  absorbs the extra width.
- **Maximum content height: `screen.visibleFrame.height - 80`.** Overflow
  scrolls vertically. Same clamping rule as today.
- **Initial position: top-right of the main screen.** Once the user
  drags, the origin is persisted via `Preferences.pinnedPanelOrigin`
  (existing behavior).
- **Row height is fixed (~32pt).** The expand state does not grow the row;
  it adds a separate drawer view below the row, indented to the app
  column. Collapsing removes the drawer. Expand/collapse is instant (no
  animation); the visible cost is one stack-view layout pass.

Each collapsed row is a single `NSGridRow` with six columns and shared
column metrics on the panel's `NSGridView`:

| # | Width   | Content                                                       |
|---|---------|---------------------------------------------------------------|
| 1 | 24pt    | App icon (resolved via bundle ID; first-letter fallback)      |
| 2 | 100pt   | App name, ellipsis-truncated                                  |
| 3 | 140pt   | Title, ellipsis-truncated                                     |
| 4 | flex    | Body, single-line ellipsis-truncated                          |
| 5 | 60pt    | Relative time, right-aligned, tabular numerals                |
| 6 | 20pt    | × dismiss button                                              |

Column gaps 10pt; panel padding 12pt. At the 600pt minimum this leaves
roughly 182pt for the body column.

The tooltip on a collapsed row shows `"<App> — <Title>\n<Body>"`, so the
user can peek at the full body without expanding.

## Interactions

- **Click on a collapsed row** (anywhere except ×): expands that row in
  place. The drawer slides down under the row, indented to the app
  column.
- **Click on an expanded row** (anywhere except × or the Open link):
  collapses it again.
- **Only one row is expanded at a time.** Clicking row B's collapsed area
  while row A is expanded collapses A and expands B.
- **× on a row**: removes that row. Panel hides if the list becomes empty.
- **Dismiss All** footer: clears the list. Panel hides.
- **`Open <App> →` in the drawer**: launches the source app via
  `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)`,
  resolved from the row's bundle ID. When the row has no bundle ID, the
  link is disabled with a tooltip explaining why.

The drawer body uses an `NSTextField` with
`usesSingleLineMode = false`, `lineBreakMode = .byWordWrapping`, and
`isSelectable = true` (so the body can be copied with Cmd-C). The text
field intercepts its own mouse events; clicks that land on selectable
text do not bubble up to the row's collapse gesture. Clicks on the
drawer's background area outside the text field do collapse the row.
There is no scroll within the drawer; wrap-only-grow is acceptable since
pinned notification bodies are short.

## Data model (Core)

```swift
public struct PinnedItem: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let appName: String
  public let bundleID: String?
  public let title: String
  public let body: String
  public let timestamp: Date
}
```

`PinnedList` (in Core):

- Stores `items: [PinnedItem]`, newest first.
- `pin(_ captured: CapturedNotification, now: Date = Date())` appends a
  new item to the front, **subject to the well-formedness gate below**.
- No collapse-by-key, no count, no entries[]. The v1 `(bundleID, title)`
  coalescing is removed.
- Hard capacity cap **100**. When the list exceeds the cap, the oldest
  item is evicted.
- `dismiss(id:)` removes by `PinnedItem.id`. `dismissAll()` clears the
  list. `isEmpty` unchanged.

### Well-formedness gate

`PinnedList.pin(_:)` refuses to append when the input is malformed.
Malformed means **either** of:

1. `title.isEmpty && body.isEmpty` — the macOS-26 SwiftUI failure mode
   collapses every text node into `appName`, leaving the other fields
   blank. Pinning would render an empty row.
2. `appName.contains(", ")` — the same failure mode joins multiple text
   nodes with `", "` into `appName`. Apps with a legitimate comma+space
   in their name (`"Calendar, Reminders"`) would be wrongly rejected.
   None ship with macOS, so the false-positive risk is low; if it ever
   becomes an issue we can tighten the rule.

When pinning is refused the banner is still **repositioned** (that path
doesn't depend on text). The refusal is logged at `debug` (so it doesn't
leak content under default settings); above-debug levels log only an
opaque `"pin skipped: malformed banner text"` line.

## Extractor improvement (defense in depth)

The v1 `BannerTextExtractor.collect(...)` walks the AX subtree and reads
`kAXValueAttribute` → `kAXTitleAttribute` → `kAXDescriptionAttribute` on
each element. On macOS 26 SwiftUI-rendered banners the AX tree
sometimes presents a single element whose `kAXDescriptionAttribute` is
a comma-joined concatenation of what used to be four separate text
nodes.

The fix walks **deeper** before accepting a single concatenated
description: when only one text-bearing element is found, the extractor
recurses past `Constants.maxAXRecursionDepth`'s normal limit looking
for `AXStaticText` descendants with their own non-empty
`kAXValueAttribute`. If structured nodes are found, those replace the
single-element fallback; if not, the extractor returns the single
fallback unchanged and the pin-gate above filters it out.

The exact predicate and depth bump are tuned during implementation
against a real macOS 26 banner; the AX tree structure isn't fully
documented and inspection is the only ground truth.

## Relative time

A pure `RelativeTime` formatter in Core (no `Foundation.DateComponentsFormatter`,
which is locale-formatted in a way we don't want for terse rendering):

| Age range          | Output           |
|--------------------|------------------|
| < 60s              | `Just now`       |
| 60s to < 60min     | `Nm ago`         |
| 60min to < 24h     | `Nh ago`         |
| 24h to < 7d        | `Nd ago`         |
| ≥ 7d               | `MMM d` (absolute, locale-neutral with `en_US_POSIX`) |

```swift
public enum RelativeTime {
  public static func format(_ instant: Date, relativeTo now: Date) -> String
}
```

A single 60-second `Timer` in `ReminderController` ticks while the panel
is visible. Each tick re-renders the time labels for all visible rows;
the underlying `PinnedItem.timestamp` is not mutated. The timer is
invalidated when the panel is ordered out.

## Capture wiring (unchanged from v1)

`BannerMover.onPin: (CapturedNotification) -> Void` still fires
exactly once per banner at first-sight. As of commit `894d81b` the
pin fires **after** `dispatchAnimation` returns, so the panel render
no longer blocks the AX-set on the first-move critical path. This
redesign keeps that ordering.

`ReminderController.capture(_:)` is unchanged at the call boundary
but its internals are rewritten to drive the new grid + drawer layout
and to drop the existing `(bundleID, title)` coalescing in
`PinnedList`.

## Failure modes

- **Malformed banner text** → pinning is skipped, repositioning still
  runs (see well-formedness gate).
- **App resolution fails** (no bundle ID resolved for the app name) →
  row still pins (we have enough data: appName, title, body, timestamp);
  the icon falls back to a first-letter glyph, and the drawer's
  `Open <App>` link is disabled.
- **`NSWorkspace.icon(forFile:)` errors or returns nil** → first-letter
  glyph fallback. The glyph is cached per `appName` (not per `bundleID`,
  so apps without a resolved bundle ID still benefit).
- **Capacity exceeded** → oldest item is silently evicted. No
  user-visible "list truncated" indicator; the cap exists to keep
  memory bounded under burst conditions, not as a feature.
- **Panel taller than the screen** → height is clamped, content
  scrolls. Same behavior as today.
- **App launch fails for `Open <App>`** → the existing
  `openApplication` completion handler logs at `error` and the row
  drawer stays open.

## Testing

Swift Testing (`@Test`, `#expect`), Core target only. The executable
target keeps its manual-test convention.

- `PinnedListTests`:
  - `pinAppendsNewest()` — new pin lands at index 0.
  - `pinPreservesPriorItems()` — second pin pushes first to index 1.
  - `capacityCapEvictsOldest()` — pinning the 101st item drops index 100.
  - `gateRejectsEmptyTitleAndBody()` — malformed input is not added.
  - `gateRejectsAppNameWithCommaSpace()` — concatenation-shaped input
    is not added.
  - `gateAcceptsNormalCapturedNotification()` — well-formed input is
    added.
  - `dismissByIDRemovesOnlyThatItem()` — existing behavior preserved.
  - `dismissAllEmpties()` — existing behavior preserved.
- `RelativeTimeTests` — boundary table, locale-stable
  (`Locale(identifier: "en_US_POSIX")`):
  - `0s` → `Just now`
  - `59s` → `Just now`
  - `60s` → `1m ago`
  - `59*60s` → `59m ago`
  - `60*60s` → `1h ago`
  - `23*60*60s` → `23h ago`
  - `24*60*60s` → `1d ago`
  - `6*24*60*60s` → `6d ago`
  - `7*24*60*60s` → date-formatted (`MMM d`)
- `BannerTextExtractorTests`: not changed in scope here. The extractor
  improvement is verified manually against real macOS 26 banners — we
  cannot construct a faithful `AXUIElement` in a unit test.

No mocks of `BannerShiftCore` types (per the project testing rules).

## Migration

This is a per-user, in-memory list; no on-disk state to migrate. The
only persisted value is `Preferences.pinnedPanelOrigin`, which carries
over. The `Rule.pinsToList` flag is unchanged. Users with the v1
behavior installed will see the new panel on the next launch.

## Risks

- **Extractor depth bump may slow first-move slightly.** The recursion
  only fires when the initial walk found a single text element; the
  common path stays as-is. Worth measuring under banner burst.
- **The `appName.contains(", ")` gate is heuristic.** No shipping app
  has a comma+space in its name today; if Apple ships one, we revisit.
- **No grouping means a burst of 30 messages from one app fills the
  panel.** The 100-item cap keeps memory bounded but the panel could
  scroll a lot. The previous design's coalescing solved this; the
  user has explicitly chosen no grouping.

## Open questions

None at design lock-in. All decisions above are settled.
