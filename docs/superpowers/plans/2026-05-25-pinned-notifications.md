# Pinned Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-on-top window that pins matching notifications and keeps them on screen after their banner disappears, with per-row dismiss, Dismiss All, and click-to-open the source app.

**Architecture:** Pure list logic (collapse/dedup/cap, newest-on-top) lives in a new `BannerShiftCore/Reminders/` module and is unit-tested with Swift Testing. `Rule` gains an additive `pinsToList` flag. `BannerMover` fires a new `onPin` callback exactly once per banner (at its existing first-sight branch) when a matched rule pins. A new exec-target `ReminderController` owns the Core list and a non-activating floating `NSPanel`.

**Tech Stack:** Swift 5.10, macOS 13+, AppKit, Accessibility, Swift Testing. Build/test via the `Makefile` (`make build`, `make test`, `make validate`).

---

## File structure

- `Sources/BannerShiftCore/Rules/Rule.swift` — **modify**: add `pinsToList` field.
- `Sources/BannerShiftCore/Reminders/CapturedNotification.swift` — **create**: immutable captured-banner snapshot.
- `Sources/BannerShiftCore/Reminders/PinnedList.swift` — **create**: `PinnedItem` + `PinnedList` collapse/dedup/cap logic.
- `Sources/BannerShiftCore/Support/Constants.swift` — **modify**: add `maxPinnedItems`.
- `Sources/BannerShiftCore/Support/Preferences.swift` — **modify**: persist the panel's frame origin.
- `Sources/BannerShift/Repositioning/BannerMover.swift` — **modify**: `onPin` callback, fired at first-sight.
- `Sources/BannerShift/UI/ReminderController.swift` — **create**: owns `PinnedList` + the floating `NSPanel`.
- `Sources/BannerShift/App/AppDelegate.swift` — **modify**: build `ReminderController`, wire `onPin`.
- `Sources/BannerShift/UI/RuleEditSheetController.swift` — **modify**: "Also pin…" checkbox.
- `Tests/BannerShiftCoreTests/Rules/RuleTests.swift` — **modify**: pinsToList default + round-trip.
- `Tests/BannerShiftCoreTests/Reminders/PinnedListTests.swift` — **create**: list behavior.

> No `CHANGELOG.md` change: nothing has shipped yet, so the changelog is left untouched until release.

---

## Task 1: Add `pinsToList` flag to `Rule`

**Files:**
- Modify: `Sources/BannerShiftCore/Rules/Rule.swift`
- Test: `Tests/BannerShiftCoreTests/Rules/RuleTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/BannerShiftCoreTests/Rules/RuleTests.swift`:

```swift
@Test func ruleDefaultsPinsToListFalse() {
  #expect(Rule().pinsToList == false)
}

@Test func ruleCodableRoundTripsPinsToList() throws {
  let rule = Rule(name: "Pin me", appPattern: "Slack", pinsToList: true)
  let data = try JSONEncoder().encode(rule)
  let back = try JSONDecoder().decode(Rule.self, from: data)
  #expect(back == rule)
  #expect(back.pinsToList == true)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `make test 2>&1 | tail -30`
Expected: compile failure — `Rule` has no `pinsToList` parameter/member.

- [ ] **Step 3: Add the field to `Rule`**

Synthesized `Codable` is used as-is (no custom decoder). Backward compatibility is **not** a goal: a rule blob persisted before this field existed will fail to decode, and `RuleStore.load()` already treats a decode failure by starting empty. New rules round-trip normally.

In `Sources/BannerShiftCore/Rules/Rule.swift`, add the stored property after `bodyPattern` (after line 51) and before `position`:

```swift
  /// When true, a matching banner is also captured into the always-on-top
  /// pinned-notifications list, in addition to any repositioning the rule
  /// performs. Defaults to false.
  public var pinsToList: Bool
```

Add the parameter to `init` (after the `bodyPattern` parameter, before `position`), with a default so existing call sites compile unchanged:

```swift
    bodyPattern: String? = nil,
    pinsToList: Bool = false,
    position: Position? = nil,
```

And assign it in the body (after `self.bodyPattern = bodyPattern`):

```swift
    self.pinsToList = pinsToList
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test 2>&1 | tail -20`
Expected: PASS, including the two new tests and the existing `ruleCodableRoundTrip` / `ruleCodableHandlesNilFields`.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Rules/Rule.swift Tests/BannerShiftCoreTests/Rules/RuleTests.swift
git commit -m "Add additive pinsToList flag to Rule

- New Bool field, defaults to false; synthesized Codable (no bw-compat)"
```

---

## Task 2: Core `CapturedNotification` value type

**Files:**
- Create: `Sources/BannerShiftCore/Reminders/CapturedNotification.swift`
- Test: covered indirectly via Task 3 (no standalone test for a plain value type)

- [ ] **Step 1: Create the file**

```swift
import Foundation

/// An immutable snapshot of one captured banner, handed to `PinnedList`.
///
/// Carries the same notification text the matcher sees, so treat it as
/// sensitive: it must never be logged outside explicit debug mode and is
/// held only in memory (never written to disk). `bundleID` is the value
/// already resolved during rule matching, reused so a row click can open the
/// source app without re-resolving.
public struct CapturedNotification: Equatable, Sendable {
  /// Localized display name of the source app (e.g. `"Slack"`).
  public let appName: String

  /// Resolved bundle identifier, or nil when no mapping was found. A nil
  /// value means a row click cannot open the source app.
  public let bundleID: String?

  /// Banner title line; part of the collapse key.
  public let title: String

  /// Banner body text; the newest body wins when a group collapses.
  public let body: String

  /// All fields default to empty so tests can build minimal fixtures.
  public init(appName: String = "", bundleID: String? = nil, title: String = "", body: String = "")
  {
    self.appName = appName
    self.bundleID = bundleID
    self.title = title
    self.body = body
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `make build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShiftCore/Reminders/CapturedNotification.swift
git commit -m "Add CapturedNotification value type for pinned list"
```

---

## Task 3: Core `PinnedItem` + `PinnedList` with collapse/dedup/cap

**Files:**
- Create: `Sources/BannerShiftCore/Reminders/PinnedList.swift`
- Modify: `Sources/BannerShiftCore/Support/Constants.swift`
- Test: `Tests/BannerShiftCoreTests/Reminders/PinnedListTests.swift`

- [ ] **Step 1: Add the cap constant**

In `Sources/BannerShiftCore/Support/Constants.swift`, add before the closing brace (after `maxBannerMatchSubjectLength`):

```swift

  /// Maximum number of rows the pinned-notifications list retains.
  ///
  /// Bounds memory and panel height against a chatty app. When a new group
  /// would exceed this, the oldest group (at the bottom of the newest-first
  /// list) is evicted. 50 comfortably covers a realistic backlog of pinned
  /// reminders without the panel growing past a screen.
  public static let maxPinnedItems: Int = 50
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/BannerShiftCoreTests/Reminders/PinnedListTests.swift`:

```swift
import Foundation
import Testing

@testable import BannerShiftCore

@Test func pinInsertsNewRow() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "Q", body: "hi"))
  #expect(list.items.count == 1)
  #expect(list.items[0].appName == "Slack")
  #expect(list.items[0].title == "Q")
  #expect(list.items[0].body == "hi")
  #expect(list.items[0].count == 1)
}

@Test func pinCollapsesSameAppAndTitle() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "Q", body: "one"))
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "Q", body: "two"))
  #expect(list.items.count == 1)
  #expect(list.items[0].count == 2)
  #expect(list.items[0].body == "two")  // newest body wins
}

@Test func pinKeepsDistinctTitlesSeparate() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Slack", title: "R"))
  #expect(list.items.count == 2)
}

@Test func pinNewestGroupOnTop() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  #expect(list.items[0].appName == "Mail")  // newest first
  #expect(list.items[1].appName == "Slack")
}

@Test func rePinBumpsGroupToTop() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))  // re-pin oldest
  #expect(list.items[0].appName == "Slack")
  #expect(list.items[0].count == 2)
  #expect(list.items.count == 2)
}

@Test func collapseKeyFallsBackToAppNameCaseInsensitively() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: nil, title: "Q"))
  list.pin(CapturedNotification(appName: "slack", bundleID: nil, title: "Q"))
  #expect(list.items.count == 1)
  #expect(list.items[0].count == 2)
}

@Test func bundleIDDistinguishesSameAppNameAndTitle() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "App", bundleID: "com.a", title: "Q"))
  list.pin(CapturedNotification(appName: "App", bundleID: "com.b", title: "Q"))
  #expect(list.items.count == 2)
}

@Test func dismissRemovesOneRow() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  let id = list.items[0].id
  list.dismiss(id: id)
  #expect(list.items.count == 1)
  #expect(list.items.allSatisfy { $0.id != id })
}

@Test func dismissAllEmpties() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  list.dismissAll()
  #expect(list.isEmpty)
}

@Test func capEvictsOldestGroup() {
  var list = PinnedList()
  for i in 0..<(Constants.maxPinnedItems + 5) {
    list.pin(CapturedNotification(appName: "App\(i)", title: "T\(i)"))
  }
  #expect(list.items.count == Constants.maxPinnedItems)
  // The 5 oldest (App0..App4) were evicted from the bottom; newest is on top.
  #expect(list.items.first?.appName == "App\(Constants.maxPinnedItems + 4)")
  #expect(list.items.contains { $0.appName == "App0" } == false)
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `make test 2>&1 | tail -30`
Expected: compile failure — no `PinnedList` / `PinnedItem`.

- [ ] **Step 4: Implement `PinnedItem` + `PinnedList`**

Create `Sources/BannerShiftCore/Reminders/PinnedList.swift`:

```swift
import Foundation

/// One row in the pinned-notifications list: a collapsed group of banners
/// sharing a `(bundleID ?? lowercased appName, title)` key, with an
/// occurrence `count` and a stable `id` for the UI.
public struct PinnedItem: Equatable, Sendable, Identifiable {
  /// Stable identity derived from the collapse key; also used as the
  /// dismiss target.
  public let id: String

  /// Display name of the source app (newest wins on collapse).
  public let appName: String

  /// Resolved bundle identifier, or nil. Used to open the source app on a
  /// row click; nil means the row is not clickable to an app.
  public let bundleID: String?

  /// Title line shared by the collapsed group.
  public let title: String

  /// Latest body text seen for this group.
  public let body: String

  /// Number of distinct banner arrivals collapsed into this row. Rendered
  /// as a badge when greater than one.
  public var count: Int
}

/// In-memory, ordered list of pinned notifications with collapse-by-key
/// semantics. Pure value type — no AppKit, no persistence; the executable
/// target holds one as mutable state and re-renders the panel after each
/// mutation.
///
/// Ordering is newest-group-first. `pin` collapses a repeat into the
/// existing group, bumps it to the top, and keeps the newest body. The list
/// is capped at `Constants.maxPinnedItems`, evicting the oldest group (at the
/// bottom) when a new group overflows it.
public struct PinnedList: Equatable {
  /// Current rows, newest group first.
  public private(set) var items: [PinnedItem] = []

  public init() {}

  /// True when no items are pinned; drives whether the panel is shown.
  public var isEmpty: Bool { items.isEmpty }

  /// Capture one notification.
  ///
  /// If a group with the same collapse key exists, increments its count,
  /// adopts the newest body and app name, and moves it to the top.
  /// Otherwise inserts a new group at the top and evicts the oldest group if
  /// the cap is exceeded.
  public mutating func pin(_ n: CapturedNotification) {
    let key = Self.collapseKey(bundleID: n.bundleID, appName: n.appName, title: n.title)
    if let index = items.firstIndex(where: { $0.id == key }) {
      let existing = items.remove(at: index)
      let updated = PinnedItem(
        id: key, appName: n.appName, bundleID: n.bundleID, title: n.title,
        body: n.body, count: existing.count + 1)
      items.insert(updated, at: 0)
      return
    }
    items.insert(
      PinnedItem(
        id: key, appName: n.appName, bundleID: n.bundleID, title: n.title, body: n.body, count: 1),
      at: 0)
    if items.count > Constants.maxPinnedItems {
      items.removeLast()
    }
  }

  /// Remove the group with `id`, if present. No-op otherwise.
  public mutating func dismiss(id: String) {
    items.removeAll { $0.id == id }
  }

  /// Remove every group.
  public mutating func dismissAll() {
    items.removeAll()
  }

  /// Collapse key: bundle ID when present (apps with the same display name
  /// stay distinct), otherwise the case-folded app name, joined to the title
  /// with a NUL that cannot appear in either field.
  private static func collapseKey(bundleID: String?, appName: String, title: String) -> String {
    let appPart = bundleID ?? appName.lowercased()
    return appPart + "\u{0}" + title
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test 2>&1 | tail -20`
Expected: PASS for all `PinnedListTests`.

- [ ] **Step 6: Commit**

```bash
git add Sources/BannerShiftCore/Reminders/PinnedList.swift \
        Sources/BannerShiftCore/Support/Constants.swift \
        Tests/BannerShiftCoreTests/Reminders/PinnedListTests.swift
git commit -m "Add PinnedList with collapse, newest-on-top, and cap

- Collapse by (bundleID ?? lowercased appName, title); newest body wins
- Re-pin bumps a group to the top; cap evicts the oldest
- Constants.maxPinnedItems = 50"
```

---

## Task 4: `BannerMover` `onPin` callback fired at first-sight

**Files:**
- Modify: `Sources/BannerShift/Repositioning/BannerMover.swift`

This is an executable-target change with no unit test (per project convention). Verified by build + manual notification testing in Task 8/9.

- [ ] **Step 1: Add the stored property and init parameter**

In `Sources/BannerShift/Repositioning/BannerMover.swift`, add a stored property after `private let animator: Animator` (line 48):

```swift
  /// Sink invoked exactly once per banner (at first-sight) when a matched
  /// rule has `pinsToList` set. Fired on the main thread, like every other
  /// method here. Defaults to a no-op so non-pinning callers need not supply
  /// it.
  private let onPin: (CapturedNotification) -> Void
```

Add the parameter to `init` (after `animator: Animator`):

```swift
    animator: Animator,
    onPin: @escaping (CapturedNotification) -> Void = { _ in }
```

And assign in the body (after `self.animator = animator`):

```swift
    self.onPin = onPin
```

- [ ] **Step 2: Carry the captured notification on `ResolvedMatch`**

Replace the `ResolvedMatch` struct (lines 237-241) with:

```swift
  private struct ResolvedMatch {
    let position: Position
    let animation: Animation
    let ruleName: String
    /// Non-nil when the matched rule pins; carries the captured fields to
    /// hand to `onPin` at first-sight.
    let pinned: CapturedNotification?
  }
```

- [ ] **Step 3: Populate `pinned` in `resolvePositionAndAnimation`**

In `resolvePositionAndAnimation` (lines 249-274), update the no-rules early return and the final return to include `pinned`:

Change the early return (line 256) to:

```swift
      return ResolvedMatch(
        position: defaultPosition, animation: .none, ruleName: "(default)", pinned: nil)
```

Replace the final `return ResolvedMatch(...)` (lines 269-273) with:

```swift
    let pinned: CapturedNotification? =
      (match?.rule.pinsToList == true)
      ? CapturedNotification(
        appName: bannerText.appName, bundleID: bannerText.bundleID,
        title: bannerText.title, body: bannerText.body)
      : nil
    return ResolvedMatch(
      position: match?.rule.position ?? defaultPosition,
      animation: match?.rule.animation ?? .none,
      ruleName: match?.rule.name ?? "(default)",
      pinned: pinned)
```

- [ ] **Step 4: Fire `onPin` at the first-sight branch**

In `processWindow`, the first-sight block currently reads (lines 174-180):

```swift
    if windowSnapshots[id] == nil {
      windowSnapshots[id] = BannerWindowSnapshot(
        originalOrigin: windowFrame.origin,
        windowFrame: windowFrame,
        bannerFrame: bannerFrame
      )
    }
```

Replace it with:

```swift
    if windowSnapshots[id] == nil {
      windowSnapshots[id] = BannerWindowSnapshot(
        originalOrigin: windowFrame.origin,
        windowFrame: windowFrame,
        bannerFrame: bannerFrame
      )
      // First sight of this banner window: capture it once, if its rule
      // pins. Re-processing the same window on later debounced passes finds
      // a non-nil snapshot and so never double-counts.
      if let pinned = resolved.pinned {
        onPin(pinned)
      }
    }
```

- [ ] **Step 5: Verify it compiles**

Run: `make build 2>&1 | tail -20`
Expected: build succeeds (the existing `BannerMover(...)` call in `AppDelegate` still compiles because `onPin` has a default).

- [ ] **Step 6: Commit**

```bash
git add Sources/BannerShift/Repositioning/BannerMover.swift
git commit -m "Fire onPin once per banner from BannerMover at first-sight

- ResolvedMatch carries the CapturedNotification when the matched rule pins
- onPin invoked inside the existing first-sight branch, so a lingering
  banner across debounce passes is captured exactly once"
```

---

## Task 5: `ReminderController` + floating panel

**Files:**
- Create: `Sources/BannerShift/UI/ReminderController.swift`
- Modify: `Sources/BannerShiftCore/Support/Preferences.swift`

Executable-target UI; verified manually in Task 9.

- [ ] **Step 1: Persist the panel frame origin in `Preferences`**

In `Sources/BannerShiftCore/Support/Preferences.swift`, add the key constant after `debugLoggingKey` (line 19):

```swift
  /// `UserDefaults` key for the pinned-list panel's saved frame origin.
  public static let pinnedPanelOriginKey = "pinnedPanelOrigin"
```

Add the accessor after the `debugLoggingEnabled` property (before the closing brace). The origin is a window position, not notification content, so persisting it is safe:

```swift
  /// Saved origin of the pinned-list panel, or nil if the user has never
  /// moved it. Stored as `"x,y"`. Only the window position is persisted;
  /// no notification content is ever written to defaults.
  public var pinnedPanelOrigin: CGPoint? {
    get {
      guard let raw = defaults.string(forKey: Self.pinnedPanelOriginKey) else { return nil }
      let parts = raw.split(separator: ",")
      guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
        return nil
      }
      return CGPoint(x: x, y: y)
    }
    set {
      guard let newValue else {
        defaults.removeObject(forKey: Self.pinnedPanelOriginKey)
        return
      }
      defaults.set("\(newValue.x),\(newValue.y)", forKey: Self.pinnedPanelOriginKey)
    }
  }
```

> `CGPoint` is available via `Foundation` (CoreGraphics is re-exported) on macOS; `Preferences.swift` already imports `Foundation`.

- [ ] **Step 2: Create `ReminderController`**

Create `Sources/BannerShift/UI/ReminderController.swift`:

```swift
import AppKit
import BannerShiftCore

/// Owns the in-memory pinned-notifications list and the always-on-top panel
/// that renders it.
///
/// `capture(_:)` is the single entry point, called on the main thread from
/// `BannerMover`'s `onPin` callback. The panel is a non-activating floating
/// `NSPanel`: it sits above other apps' windows, follows the user across
/// Spaces, shows over full-screen apps, and never steals keyboard focus when
/// a row is clicked. It is shown when the list becomes non-empty and ordered
/// out when the last item is dismissed. AppKit, main-thread only.
final class ReminderController: NSObject, NSWindowDelegate {
  private var list = PinnedList()
  private let preferences: Preferences
  private var panel: NSPanel?
  private var stack: NSStackView?

  init(preferences: Preferences) {
    self.preferences = preferences
    super.init()
  }

  /// Capture one notification into the list and refresh the panel.
  func capture(_ notification: CapturedNotification) {
    list.pin(notification)
    render()
  }

  // MARK: List mutations from the UI

  @objc private func dismissRow(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue else { return }
    list.dismiss(id: id)
    render()
  }

  @objc private func dismissAll() {
    list.dismissAll()
    render()
  }

  @objc private func openSourceApp(_ sender: NSClickGestureRecognizer) {
    guard let bundleID = sender.view?.identifier?.rawValue, !bundleID.isEmpty,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  // MARK: Rendering

  /// Rebuild the row views from the current list and show or hide the panel.
  private func render() {
    if list.isEmpty {
      panel?.orderOut(nil)
      return
    }
    let panel = ensurePanel()
    let stack = self.stack ?? NSStackView()
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for item in list.items {
      stack.addArrangedSubview(rowView(for: item))
    }
    stack.addArrangedSubview(footerView())
    panel.layoutIfNeeded()
    panel.orderFrontRegardless()  // show without activating BannerShift
  }

  /// Build a single row: app name + count badge, title, truncated body, and a
  /// dismiss button. Clicking the row (outside the button) opens the app.
  private func rowView(for item: PinnedItem) -> NSView {
    let appTitle = item.count > 1 ? "\(item.appName) ·\(item.count)" : item.appName
    let appLabel = makeLabel(appTitle, weight: .semibold, size: 12)
    let titleLabel = makeLabel(item.title, weight: .regular, size: 12)
    let bodyLabel = makeLabel(item.body, weight: .regular, size: 11)
    bodyLabel.textColor = .secondaryLabelColor
    bodyLabel.lineBreakMode = .byTruncatingTail
    bodyLabel.maximumNumberOfLines = 2

    let text = NSStackView(views: [appLabel, titleLabel, bodyLabel])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    text.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let dismiss = NSButton(title: "\u{00D7}", target: self, action: #selector(dismissRow(_:)))
    dismiss.bezelStyle = .circular
    dismiss.identifier = NSUserInterfaceItemIdentifier(item.id)
    dismiss.setContentHuggingPriority(.defaultHigh, for: .horizontal)

    let row = NSStackView(views: [text, dismiss])
    row.orientation = .horizontal
    row.alignment = .top
    row.spacing = 8
    row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    // Row click opens the source app; carry the bundle ID on the row's
    // identifier so the gesture handler can resolve it. Empty when unknown.
    row.identifier = NSUserInterfaceItemIdentifier(item.bundleID ?? "")
    let click = NSClickGestureRecognizer(target: self, action: #selector(openSourceApp(_:)))
    row.addGestureRecognizer(click)
    return row
  }

  /// Trailing "Dismiss All" footer button.
  private func footerView() -> NSView {
    let button = NSButton(title: "Dismiss All", target: self, action: #selector(dismissAll))
    button.bezelStyle = .rounded
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let footer = NSStackView(views: [spacer, button])
    footer.orientation = .horizontal
    footer.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 8, right: 10)
    return footer
  }

  private func makeLabel(_ text: String, weight: NSFont.Weight, size: CGFloat) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    return field
  }

  // MARK: Panel construction

  /// Lazily build the floating panel, restoring its saved origin.
  private func ensurePanel() -> NSPanel {
    if let panel { return panel }

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
    stack.translatesAutoresizingMaskIntoConstraints = false
    self.stack = stack

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
      styleMask: [.titled, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.title = "Pinned Notifications"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.delegate = self

    guard let content = panel.contentView else { return panel }
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      content.widthAnchor.constraint(equalToConstant: 320),
    ])

    if let origin = preferences.pinnedPanelOrigin {
      panel.setFrameOrigin(origin)
    } else {
      positionTopRight(panel)
    }
    self.panel = panel
    return panel
  }

  /// Default placement: top-right of the main screen's visible area.
  private func positionTopRight(_ panel: NSPanel) {
    guard let screen = NSScreen.main else { return }
    let visible = screen.visibleFrame
    let size = panel.frame.size
    let origin = CGPoint(
      x: visible.maxX - size.width - 20,
      y: visible.maxY - size.height - 20)
    panel.setFrameOrigin(origin)
  }

  // MARK: NSWindowDelegate

  /// Remember the dragged position (origin only — not notification content).
  func windowDidMove(_ notification: Notification) {
    guard let panel else { return }
    preferences.pinnedPanelOrigin = panel.frame.origin
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `make build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/BannerShift/UI/ReminderController.swift Sources/BannerShiftCore/Support/Preferences.swift
git commit -m "Add ReminderController and always-on-top pinned-list panel

- Non-activating floating NSPanel, joins all Spaces, over full-screen
- Row click opens the source app; per-row dismiss and Dismiss All
- Panel frame origin persisted (window position only, no content)"
```

---

## Task 6: Wire `ReminderController` into `AppDelegate`

**Files:**
- Modify: `Sources/BannerShift/App/AppDelegate.swift`

- [ ] **Step 1: Add the stored property**

In `Sources/BannerShift/App/AppDelegate.swift`, add after `private let notificationPresenter = TestNotificationPresenter()` (line 24):

```swift
  /// Owns the pinned-notifications list and its always-on-top panel. Built in
  /// `applicationDidFinishLaunching` and fed by `BannerMover`'s `onPin`.
  private let reminderController = ReminderController(preferences: Preferences())
```

> Note: this constructs its own `Preferences` instance. `Preferences` reads live from `UserDefaults` on every access (no in-process cache, per its doc comment), so a second instance shares the same backing store as `self.preferences`. That is consistent with how `RuleEditorWindowController` and others hold their own references.

- [ ] **Step 2: Pass `onPin` into the `BannerMover`**

In `applicationDidFinishLaunching`, update the `BannerMover` construction (lines 96-102) to add the `onPin` argument:

```swift
    let mover = BannerMover(
      logger: logger,
      preferences: preferences,
      ruleStore: ruleStore,
      matcher: matcher,
      animator: animator,
      onPin: { [weak self] captured in self?.reminderController.capture(captured) }
    )
```

- [ ] **Step 3: Verify it compiles**

Run: `make build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/BannerShift/App/AppDelegate.swift
git commit -m "Wire BannerMover onPin to ReminderController.capture"
```

---

## Task 7: "Also pin…" checkbox in the rule editor

**Files:**
- Modify: `Sources/BannerShift/UI/RuleEditSheetController.swift`

- [ ] **Step 1: Add the checkbox control**

In `Sources/BannerShift/UI/RuleEditSheetController.swift`, add after the `animationPopUp` declaration (line 30):

```swift
  private let pinButton = NSButton(
    checkboxWithTitle: "Also pin to the always-on-top list", target: nil, action: nil)
```

- [ ] **Step 2: Add it to the Action section of the grid**

In `makeGrid()`, add a row after the Animation row in the grid array (after line 130 `[rightLabel("Animation:"), animationPopUp],`):

```swift
      [NSGridCell.emptyContentView, pinButton],
```

> The grid currently has 12 rows (indices 0-11); this adds index 12. The merged/padded row indices referenced later (`[2, 8, 9]`, `row(at: 2)`, `row(at: 9)`) are unaffected because the new row is appended at the end.

- [ ] **Step 3: Load and collect the value**

In `loadFields()`, add after the `animationPopUp.selectItem(...)` call (after line 218):

```swift
    pinButton.state = rule.pinsToList ? .on : .off
```

In `collectRule()`, add `pinsToList` to the returned `Rule` initializer (after the `bodyPattern:` argument, before `position:`):

```swift
      bodyPattern: nilIfEmpty(bodyField.stringValue),
      pinsToList: pinButton.state == .on,
      position: positionIndex == 0 ? nil : Position.allCases[positionIndex - 1],
```

- [ ] **Step 4: Update the type's doc comment**

The class doc comment (lines 5-15) says the form is "split into a Match section (the criteria) and an Action section (position and animation)." Update the trailing clause to:

```
/// section (the criteria) and an Action section (position, animation, and
/// whether to pin the banner to the always-on-top list).
```

- [ ] **Step 5: Verify it compiles**

Run: `make build 2>&1 | tail -20`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/BannerShift/UI/RuleEditSheetController.swift
git commit -m "Add 'Also pin to the always-on-top list' option to rule editor"
```

> **Changelog:** intentionally not updated. Nothing has shipped yet; the
> changelog is populated at release time, not incrementally during v1 work.

---

## Task 8: Validate and manually verify

**Files:** none (verification only)

- [ ] **Step 1: Run the full pre-merge gate**

Run: `make validate`
Expected: lint clean, build succeeds, all tests pass. If swift-format/SwiftLint flags the new files, run `make format` then re-run `make validate`; fix any remaining lint by changing the code (do not add blanket disables — see project linting rules).

- [ ] **Step 2: Build and launch the app**

Run: `make run`
Expected: BannerShift launches as a menu-bar agent (grant Accessibility if prompted).

- [ ] **Step 3: Create a pinning rule**

In the menu bar → Rules…, add a rule that matches the test notification (e.g. App pattern `*` is too broad; use a specific App or Title pattern that matches the built-in `TestNotification`). Check **"Also pin to the always-on-top list"**, set a position, Done.

- [ ] **Step 4: Verify pinning and de-dup**

Trigger the test notification (menu bar → Send Test Notification, or the relevant menu item). Confirm:
- The banner repositions per the rule (existing behavior), AND a panel appears at top-right showing the pinned row.
- Sending the same matching notification again increments the count badge (`·2`) rather than adding a second row, and bumps it to the top.
- Sending a matching notification with a different title adds a second row above the first.

- [ ] **Step 5: Verify always-on-top, dragging, interaction, and lifecycle**

- Bring another app forward / enter full-screen: the panel stays visible on top and does not steal focus.
- Drag the panel; quit and relaunch (`make run`): it reappears at the dragged position when the next item is pinned.
- Click a row: its source app comes forward.
- Click × on a row: that row disappears. Click "Dismiss All": the panel empties and orders itself out.
- Confirm the list does **not** survive quitting the app (in-memory only): quit, relaunch, and the panel stays hidden until a new matching notification arrives.

- [ ] **Step 6: Periodic dead-code check**

Run: `make analyze`
Expected: no new `unused_declaration` / `unused_import` findings attributable to the new files. Investigate any (treat as leads, not verdicts, per project rules).

---

## Self-review notes

- **Spec coverage:** additive flag (Task 1, 7), in-memory only / no disk for content (Tasks 3, 5 — only the panel origin is persisted), visible-when-non-empty (Task 5 `render`), always-on-top non-activating (Task 5 panel config), collapse by (app,title) with count + newest body (Task 3), newest-on-top + re-pin bump (Task 3), row click activates app (Task 5), draggable + remembered (Task 5 + Preferences), cap (Task 3), idempotency per banner (Task 4 first-sight), Core tests exhaustive / exec manual (Tasks 3, 8). All covered. Changelog deliberately omitted (nothing released yet).
- **Type consistency:** `CapturedNotification(appName:bundleID:title:body:)`, `PinnedItem(id:appName:bundleID:title:body:count:)`, `PinnedList.pin/dismiss(id:)/dismissAll/isEmpty/items`, `Rule.pinsToList`, `Preferences.pinnedPanelOrigin`, `BannerMover(onPin:)`, `ReminderController(preferences:).capture(_:)` are used consistently across tasks.
