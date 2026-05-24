# Alert Cue — Design

Status: approved for planning (2026-05-24)
Branch: `feature/alert-cue` (off `feature/v1-implementation`)

## Summary

Add a second, independent kind of user rule: an **alert rule**. When a native
notification banner matches an alert rule, BannerShift records it and shows a
persistent, manually-dismissed **alert card**: a floating, non-activating
overlay that lists every still-active alert, one truncated line each, newest on
top. The card never auto-dismisses; the user clears entries individually (a per-
row close button revealed on hover) or all at once.

This is a reaction layer on top of the same banner-detection BannerShift already
performs for repositioning. It does not block, pin, extend, or alter the OS
notification in any way (those are impossible under the AX-only model, see the
Non-goals). It only observes a banner and draws our own UI in response.

## Motivation

Native banners auto-dismiss in roughly five seconds. The notifications a user
most wants to catch (a message from a specific person, an alert from a specific
app) are exactly the ones that hurt most to miss. Repositioning helps the user
notice them; it does not help when the user was away from the screen. An alert
card that persists until acknowledged closes that gap without leaving the safe,
observe-and-reposition boundary the app already lives within.

## Goals

- A separate alert-rule type, matched on the same fields as positioning rules
  (app, bundle ID, title, subtitle, body), with its own persisted list and its
  own editor window.
- A floating alert card that aggregates all active alerts as a scrollable,
  newest-first list, one truncated line per entry (`app · title: body`).
- Per-row dismissal (hover-revealed close button) and a Dismiss-all control.
- Card position chosen from the existing 3x3 `Position` grid, on the main
  screen, configurable from the menu.
- No new permissions, no new entitlements, no new OS-internal dependencies.

## Non-goals

- Blocking, pinning, extending the lifetime of, or re-rendering the OS
  notification. The AX-only model cannot do this; see the prior feasibility
  discussion. The alert card is our own window showing our own distilled copy
  of the text, not the live notification.
- Writing notification content (title/subtitle/body) to disk. Alert *rules*
  persist; alert *entries* are in-memory only and are lost on quit. This is a
  hard constraint from the project content-handling rule, not a fork.
- Notification-style re-posting (UserNotifications), screen capture, or any
  app-launch / shell / automation action. Those are a separate, deliberate
  product decision and are explicitly out of scope here.
- Multiple card display modes, per-rule cue styling (color/sound), and
  multi-display placement. The design leaves room for a second display mode
  later but ships exactly one mode now.

## Architecture: scan once, fan out

Today `BannerMover.process(notificationUIWindows:)` owns the per-pass window
loop and, inside it, finds the banner, reads frames, and extracts `BannerText`.
Adding alerts as a second consumer of that work should not bolt the alert logic
onto the mover. Instead the shared per-window work moves up into a new stage
that fans each result out to independent handlers.

```
AX notification → Debouncer → AppDelegate
        │
        ▼
  BannerScanner.process(notificationUIWindows:)     shared stage, once per window:
        │   panel?      → handler.bannerAbsent(...)    panel detection
        │   no banner?  → handler.bannerAbsent(...)    AXBannerFinder.find + frames
        │   banner?     → build BannerObservation      BannerTextExtractor + bundle resolve
        │                 → handler.bannerPresent(obs)
        │
        ├───────────────────────┬───────────────────────
        ▼                       ▼
   BannerMover             AlertEvaluator                 independent BannerHandlers
   (move / restore)        (match alert rules,
                            dedup per windowID,
                            append AlertEntry)
                                 │
                                 ▼
                        AlertOverlayController (renders the card)
```

Properties:

- The expensive, fragile AX work (panel detection, banner-find, frame reads,
  text extraction, bundle resolution) happens exactly once per window per pass.
  This is cost-neutral versus today, because the mover already extracts text on
  every pass.
- `BannerMover` and `AlertEvaluator` are peers. Neither references the other.
  A third handler can be added later by appending to the scanner's handler list.
- The mover shrinks to "given an observation, move; on absent, restore; on
  reset, clear," which is a cleaner single responsibility than today.

The protocol is named `BannerHandler` (not `BannerObserver`) to avoid colliding
with the existing AX `AXObserverController` concept.

## Components

### Core (pure, unit-tested, no AppKit/AX)

**`MatchCriteria`** — the five optional regex patterns extracted into one value
type:

```swift
public struct MatchCriteria: Equatable, Sendable {
  public var appPattern: String?
  public var bundleIDPattern: String?
  public var titlePattern: String?
  public var subtitlePattern: String?
  public var bodyPattern: String?
}
```

This is the *matching* half of the shared logic. It is worth extracting even at
two call sites because the compile/option-set/subject-cap logic in
`RuleMatcher.check` is intricate and security-sensitive; duplicating it would
mean two places to fix the next backtracking or redaction bug.

**`Matchable`** — the small protocol both rule kinds adopt:

```swift
public protocol Matchable {
  var id: String { get }
  var name: String { get }
  var enabled: Bool { get }
  var criteria: MatchCriteria { get }
}
```

**`Rule`** (existing) — keeps its current *flat* stored pattern fields so its
persisted JSON shape does not change (backward compatibility: existing saved
rules must still decode). It gains a computed `var criteria: MatchCriteria` that
reads the flat fields, and conforms to `Matchable`. No stored-property or
Codable changes.

**`AlertRule`** (new) — `id`, `name`, `enabled`, and a stored `criteria`.
`Codable` + `Identifiable` + `Sendable`. No position or animation. Conforms to
`Matchable`.

**`RuleMatcher`** (existing) — refactored so the private match check operates on
`MatchCriteria`. Adds one generic entry point used by both kinds:

```swift
public func firstMatch<R: Matchable>(in rules: [R], banner: BannerText) -> R?
```

The current `match(rules: [Rule], banner:) -> RuleMatch?` stays as a thin
wrapper over `firstMatch` so `BannerMover` and the rule editor are untouched.
The pattern-string-keyed regex cache is shared automatically across both rule
kinds, so a single shared `RuleMatcher` instance serves both handlers.

**`AlertEntry`** (new) — the distilled, displayable record of one matched
notification. No AX references, so it safely outlives the OS banner and the
notification process:

```swift
public struct AlertEntry: Equatable, Sendable, Identifiable {
  public let id: String        // fresh UUID per appearance
  public let appName: String
  public let title: String
  public let body: String
  public let ruleName: String  // which alert rule matched (diagnostic / future display)
  public let date: Date

  /// One-line summary: "appName · title: body", truncated to maxLength with an
  /// ellipsis. Omits the ": body" / ": " join cleanly when fields are empty.
  public func oneLine(maxLength: Int) -> String
}
```

The leading bullet glyph is a view concern and is not part of `oneLine`.

**`AlertList`** (new) — pure reducer over the entries, newest-first:

```swift
public struct AlertList: Equatable {
  public private(set) var entries: [AlertEntry]   // index 0 == newest
  public init()
  public mutating func append(_ entry: AlertEntry) // insert at front; enforce safety cap
  public mutating func dismiss(id: String)
  public mutating func dismissAll()
}
```

There is no user-visible eviction (the card scrolls). A high internal safety cap
(`Constants.alertListSafetyCap`, on the order of a few hundred) drops the oldest
entries only to bound memory if the user is away for a very long time.

### Executable (AppKit + AX)

**`BannerObservation`** (new struct) — the fan-out payload, bundling the AX
handles the mover needs and the distilled text the evaluator needs:

```swift
struct BannerObservation {
  let windowID: UInt64
  let window: AXUIElement
  let banner: AXUIElement
  let windowFrame: CGRect
  let bannerFrame: CGRect
  let text: BannerText        // bundle ID already resolved by the scanner
}
```

**`BannerHandler`** (new protocol):

```swift
protocol BannerHandler: AnyObject {
  func bannerPresent(_ observation: BannerObservation)
  func bannerAbsent(windowID: UInt64, window: AXUIElement)
  func notificationUIDidReset()
}
```

**`BannerScanner`** (new) — owns the per-pass window loop, panel detection,
`AXBannerFinder.find`, frame reads, `BannerTextExtractor.extract`, and
`AppResolver` bundle resolution (moved out of `BannerMover`). Builds a
`BannerObservation` and calls `bannerPresent` on each handler; calls
`bannerAbsent` for panels and bannerless windows; `reset()` calls
`notificationUIDidReset` on each handler. Holds a fixed, injected
`[BannerHandler]`; no dynamic registration.

**`BannerMover`** (existing, refactored) — conforms to `BannerHandler`. Loses
its window-list loop and its own text extraction; receives `BannerText` via the
observation. Keeps `windowSnapshots`, `makeCalculator`, `dispatchAnimation`,
`restoreIfNeeded`. `bannerPresent` resolves position from positioning rules and
animates; `bannerAbsent` restores; `notificationUIDidReset` runs the existing
`reset()`.

**`AlertEvaluator`** (new) — conforms to `BannerHandler`. Holds the shared
`RuleMatcher`, the `AlertRuleStore`, a reference to the overlay controller, and a
`Set<UInt64>` of already-alerted window IDs (the dedup key).
- `bannerPresent(obs)`: if `obs.windowID` is already alerted, return. Otherwise
  `firstMatch(in: alertRuleStore.load(), banner: obs.text)`; on a match build an
  `AlertEntry`, hand it to the overlay controller, and insert the window ID into
  the alerted set.
- `bannerAbsent(windowID:)`: remove the window ID from the alerted set, so a
  later banner reusing that window can alert again.
- `notificationUIDidReset()`: clear the alerted set only. **Alert entries are not
  cleared here** — `reset` means the AX elements went invalid, not that the user
  acknowledged anything. Entries are AX-free values and persist across a
  notification-process restart until the user dismisses them.

This split matters: `reset` clears AX-derived state (snapshots, dedup keys) but
never user-facing alert entries.

**`AlertRuleStore`** (new) — `[AlertRule]` as a JSON blob in `UserDefaults` under
key `"alertRules"`, with the same decoded-list cache as `RuleStore`. The ~30-line
store skeleton is **duplicated**, not generalized: the divergence cost is low and
there are only two stores (per the no-premature-abstraction rule).

**`AlertOverlayController`** (new) — owns an `AlertList` and a card-sized,
non-activating `NSPanel`:
- Non-activating (`.nonactivatingPanel`) so clicking the close buttons never
  brings BannerShift to the foreground or steals focus.
- High window level (floating / status level), `collectionBehavior` including
  `.canJoinAllSpaces` and `.stationary` so it shows across Spaces and does not
  travel with Mission Control.
- The window spans only the card, so clicks outside the card naturally fall
  through to whatever is behind it; no explicit click-through plumbing needed.
- Renders a scrollable list (`NSScrollView` over a stack/table) with a maximum
  height; below the cap the card sizes to content, above it the card scrolls.
  Each row shows a bullet, the entry's `oneLine`, and a close (x) button shown on
  hover. A header carries a Dismiss-all button.
- Positioned at the configured `Position` cell on the main screen. Shows when
  the first entry arrives; hides when the list empties.

### Wiring (`AppDelegate`)

- Construct one shared `RuleMatcher`.
- Construct `BannerMover` and `AlertEvaluator` as handlers.
- Construct `BannerScanner(handlers: [bannerMover, alertEvaluator])`.
- The debounced AX handler calls `scanner.process(notificationUIWindows:)`; the
  notification-process-exit path calls `scanner.reset()` (replacing today's
  direct `bannerMover` calls).

### Editor (separate window, shared form)

The alert editor is a separate window (`AlertRuleEditorWindowController`) opened
from a new "Alert Rules..." menu item. To avoid duplicating ~400 lines, extract
the shared parts of the current `RuleEditorWindowController` into one reusable
component:
- the name field, enabled checkbox, and five regex fields with live
  `RuleMatcher.compileForMatching` validation, and
- the "test against sample text" tester.

`RuleEditorWindowController` keeps its position/animation row and embeds the
shared form; `AlertRuleEditorWindowController` embeds the same form with no extra
controls. This refactors existing, working editor code; the change is justified
by the intricacy of the validation logic (one place to maintain), and must
preserve current behavior of the positioning editor.

### Preferences and menu

- New preference `alertCardPosition: Position` (default `.topRight`, since a
  growing stack reads best out of a corner). Stored via the existing
  `Preferences` type / `UserDefaults`.
- `MenuBarController` gains an "Alert Rules..." item (opens the alert editor) and
  an alert-card position submenu reusing the `Position` cases.

## Data flow (end to end)

1. AX posts a notification-UI change; the `Debouncer` coalesces the burst.
2. `AppDelegate` calls `BannerScanner.process(notificationUIWindows:)`.
3. For each window the scanner classifies it (panel / no banner / banner) and,
   for a banner, builds a `BannerObservation` with resolved `BannerText`.
4. The scanner fans the result out: `BannerMover` moves or restores;
   `AlertEvaluator` matches alert rules and, on a first-seen match for that
   window, appends an `AlertEntry`.
5. `AlertOverlayController` re-renders, showing the card if it was hidden.
6. When the banner goes away, the scanner calls `bannerAbsent`; the mover
   restores the window and the evaluator drops the dedup key.
7. The user clicks a row's close button or Dismiss-all; the `AlertList` updates
   and the card re-renders, hiding when empty.

## Error handling and edge cases

- **Malformed alert-rule regex**: identical to positioning rules. The shared
  matcher emits a diagnostic and treats the offending rule as disabled for that
  match; it never crashes the pass or blocks other rules.
- **Burst of repeated AX events for one banner**: dedup by window ID guarantees
  at most one entry per banner appearance.
- **Window ID reuse**: AX element IDs are pointer bit patterns and can be
  reused. Clearing the dedup key on `bannerAbsent` ensures a reused ID can alert
  again for a genuinely new banner.
- **Notification process restart**: `notificationUIDidReset` invalidates AX
  state but preserves alert entries (they hold no AX references).
- **No main screen / display change**: the overlay recomputes its frame from the
  current main screen on each render; if no screen is available it stays hidden.
- **App quit**: entries are in-memory and are gone, by design.

## Testing

Core (Swift Testing, exhaustive on the logic):
- `RuleMatcher.firstMatch` over `MatchCriteria`: adapt existing `RuleMatcher`
  tests; add `AlertRule` matching cases (AND across fields, wildcard on
  empty/nil, case-insensitivity, malformed-pattern-disables-rule).
- `Rule.criteria`: flat-field to criteria mapping; confirm existing `Rule` JSON
  still decodes unchanged (backward-compatibility guard).
- `AlertEntry.oneLine`: truncation at `maxLength` with ellipsis; field joining;
  empty title; empty body; over-long body; grapheme-cluster safety.
- `AlertList`: `append` inserts newest-first; `dismiss(id:)` removes the right
  entry; `dismissAll` empties; safety-cap evicts oldest beyond the bound while
  preserving order.

Executable (manual, per project convention; no unit tests on the executable):
- Overlay render, scroll past max height, hover close button, Dismiss-all,
  grid positioning on the main screen.
- Evaluator dedup across an event burst.
- Entry persistence across a notification-process restart; clear on quit.

## Security, permissions, fragility

- No new entitlements; `Resources/BannerShift.entitlements` is unchanged.
- No new permission prompts: the card is our own `NSPanel`, not a posted
  `UNNotification`, and there is no screen capture.
- Notification content lives only in memory and only on screen; it is never
  written to disk. `AlertEntry` is deliberately non-`Codable` to make that hard
  to violate by accident.
- No new OS-internal constants. The scanner reuses the existing banner subroles,
  panel identifier, and full-screen-container invariant already centralized in
  `Constants.swift`.

## Changelog

Add under `## [Unreleased]` / `Added`:

> Alert rules: flag chosen notifications and collect them in a persistent,
> manually-dismissed on-screen list, so you can catch important banners you
> would otherwise miss when away from the screen.

## Open items

- Hub name: `BannerScanner` (current pick) versus `BannerDispatcher` /
  `BannerRouter`. Rename is cheap if preferred during review.
- Default `alertCardPosition`: proposed `.topRight`; confirm.
