# Rules Editor Wildcards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace regex rule patterns with simple wildcards, make empty rules match nothing, add an app chooser, and separate the matcher from the action on the edit sheet.

**Architecture:** A new pure `WildcardPattern` value type in `BannerShiftCore` translates `*`-wildcards to regex; `RuleMatcher` compiles through it and treats a criteria-less rule as a non-match. The AppKit `RuleEditSheetController` drops regex validation, adds `NSOpenPanel` app choosers, and groups fields into Match/Action sections. Builds on the in-tree list+sheet rule-editor redesign (uncommitted working-tree state); temporary launch scaffolding in `AppDelegate` (auto-show + seed) stays until the final task so the sheets can be screenshot-verified.

**Tech Stack:** Swift 5.10, SwiftPM, Swift Testing (`@Test`/`#expect`), AppKit (`NSGridView`, `NSOpenPanel`), `UniformTypeIdentifiers`.

---

### Task 1: WildcardPattern value type (Core)

**Files:**
- Create: `Sources/BannerShiftCore/Rules/WildcardPattern.swift`
- Test: `Tests/BannerShiftCoreTests/Rules/WildcardPatternTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/BannerShiftCoreTests/Rules/WildcardPatternTests.swift`:

```swift
import Testing

@testable import BannerShiftCore

@Test func starBecomesDotStar() {
  #expect(WildcardPattern.regexPattern(from: "*") == ".*")
  #expect(WildcardPattern.regexPattern(from: "Slack*") == "Slack.*")
  #expect(WildcardPattern.regexPattern(from: "*meeting*") == ".*meeting.*")
}

@Test func metacharactersAreEscapedToLiterals() {
  // A bundle id's dots must match literally, not as regex "any character".
  #expect(WildcardPattern.regexPattern(from: "com.apple.mail") == "com\\.apple\\.mail")
  // Brackets, anchors, and quantifiers are literal text under wildcards.
  #expect(WildcardPattern.regexPattern(from: "[x]") == "\\[x\\]")
  #expect(WildcardPattern.regexPattern(from: "^DM") == "\\^DM")
}

@Test func emptyWildcardProducesEmptyPattern() {
  #expect(WildcardPattern.regexPattern(from: "") == "")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WildcardPattern 2>&1 | tail -20`
Expected: compile failure — `cannot find 'WildcardPattern' in scope`.

- [ ] **Step 3: Implement WildcardPattern**

Create `Sources/BannerShiftCore/Rules/WildcardPattern.swift`:

```swift
import Foundation

/// Translates a user-facing wildcard pattern into a regex pattern string.
///
/// BannerShift rule fields accept simple wildcards rather than full regular
/// expressions: `*` matches any run of characters and every other character is
/// matched literally. This keeps rule authoring approachable while still
/// reusing the `Regex` engine for the actual comparison. The result is meant
/// to be compiled unanchored (substring) and case-insensitively; `RuleMatcher`
/// applies those options, not this type.
public enum WildcardPattern {
  /// Regex metacharacters escaped so they match literally. `*` is excluded on
  /// purpose: it is the one wildcard character and is translated to `.*`.
  private static let metacharacters: Set<Character> = [
    "\\", "^", "$", ".", "|", "?", "+", "(", ")", "[", "]", "{", "}",
  ]

  /// Translate `wildcard` into a regex pattern string: each `*` becomes `.*`;
  /// every other character is emitted literally (metacharacters escaped).
  public static func regexPattern(from wildcard: String) -> String {
    var pattern = ""
    for character in wildcard {
      if character == "*" {
        pattern += ".*"
      } else if metacharacters.contains(character) {
        pattern.append("\\")
        pattern.append(character)
      } else {
        pattern.append(character)
      }
    }
    return pattern
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WildcardPattern 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Rules/WildcardPattern.swift Tests/BannerShiftCoreTests/Rules/WildcardPatternTests.swift
git commit -m "Add WildcardPattern: translate user wildcards to regex"
```

---

### Task 2: RuleMatcher wildcard + empty-rule semantics (Core)

**Files:**
- Modify: `Sources/BannerShiftCore/Rules/RuleMatcher.swift`
- Test: `Tests/BannerShiftCoreTests/Rules/RuleMatcherTests.swift`

- [ ] **Step 1: Update the tests to encode the new semantics**

Replace the full contents of `Tests/BannerShiftCoreTests/Rules/RuleMatcherTests.swift` with:

```swift
import Testing

@testable import BannerShiftCore

private let matcher = RuleMatcher()

@Test func emptyRulesReturnNil() {
  #expect(matcher.match(rules: [], banner: BannerText(appName: "X")) == nil)
}

@Test func ruleWithNoPatternsMatchesNothing() {
  // A rule with no criteria is a no-op, not a catch-all.
  let empty = Rule(name: "Empty")
  #expect(matcher.match(rules: [empty], banner: BannerText(appName: "Whatever")) == nil)
}

@Test func appPatternMatchesCaseInsensitively() {
  let rule = Rule(name: "Slack rule", appPattern: "slack")
  let match = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == rule.id)
}

@Test func allSetPatternsMustMatch() {
  // Wildcard "DM*" matches a title that starts with DM; AND'd with the app.
  let rule = Rule(name: "Slack DMs", appPattern: "Slack", titlePattern: "DM*")
  let dm = matcher.match(
    rules: [rule], banner: BannerText(appName: "Slack", title: "DM from Alice"))
  let chn = matcher.match(rules: [rule], banner: BannerText(appName: "Slack", title: "#general"))
  #expect(dm?.rule.id == rule.id)
  #expect(chn == nil)
}

@Test func firstMatchWins() {
  let firstRule = Rule(name: "A", appPattern: "Slack", position: .middle)
  let secondRule = Rule(name: "B", appPattern: "Slack", position: .topRight)
  let match = matcher.match(
    rules: [firstRule, secondRule], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == firstRule.id)
}

@Test func disabledRuleSkipped() {
  let disabled = Rule(name: "Off", enabled: false, appPattern: "Slack", position: .topLeft)
  let live = Rule(name: "On", appPattern: "Slack", position: .middle)
  let match = matcher.match(rules: [disabled, live], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == live.id)
}

@Test func bundleIDPatternMatchedAgainstResolvedID() {
  // Substring wildcard against the resolved bundle id.
  let rule = Rule(name: "Slack only", bundleIDPattern: "tinyspeck")
  let with = matcher.match(
    rules: [rule],
    banner: BannerText(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"))
  let without = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(with != nil)
  #expect(without == nil)
}

@Test func literalDotInBundlePatternIsNotWildcard() {
  // The dot in a bundle pattern matches a literal dot, not any character.
  let rule = Rule(name: "Mail", bundleIDPattern: "com.apple.mail")
  let hit = matcher.match(
    rules: [rule], banner: BannerText(appName: "Mail", bundleID: "com.apple.mail"))
  let miss = matcher.match(
    rules: [rule], banner: BannerText(appName: "Mail", bundleID: "comXappleXmail"))
  #expect(hit != nil)
  #expect(miss == nil)
}

@Test func starMatchesAcrossNewlinesInBody() {
  // `*` becomes `.*` and the matcher applies dotMatchesNewlines, so a star
  // spans embedded newlines in multi-line banner text.
  let rule = Rule(name: "multiline", bodyPattern: "alice*bob")
  let banner = BannerText(appName: "X", body: "alice\nsays\nbob")
  #expect(matcher.match(rules: [rule], banner: banner) != nil)
}

@Test func invalidateCacheClearsCompiledPatterns() {
  let isolatedMatcher = RuleMatcher()
  let rule = Rule(name: "r", appPattern: "Slack")
  #expect(isolatedMatcher.match(rules: [rule], banner: BannerText(appName: "Slack")) != nil)
  isolatedMatcher.invalidateCache()
  #expect(isolatedMatcher.match(rules: [rule], banner: BannerText(appName: "Slack")) != nil)
}

@Test func compileForMatchingAppliesIgnoresCase() throws {
  let regex = try RuleMatcher.compileForMatching("slack")
  #expect("SLACK".firstMatch(of: regex) != nil)
}
```

Note: this removes `ruleWithNoPatternsIsCatchall`, `malformedRegexDoesNotMatch`,
`malformedRegexInvokesDiagnosticLogger`, and `malformedRuleDoesNotBlockValidNextRule`
(malformed input is impossible under wildcards) and adds `ruleWithNoPatternsMatchesNothing`,
`literalDotInBundlePatternIsNotWildcard`, and `starMatchesAcrossNewlinesInBody`.

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `swift test --filter RuleMatcher 2>&1 | tail -30`
Expected: FAIL — `ruleWithNoPatternsMatchesNothing` returns a match (current code is catch-all),
and `literalDotInBundlePatternIsNotWildcard` miss-case wrongly matches (dot is regex-any today).

- [ ] **Step 3: Translate wildcards in `compileForMatching`**

In `Sources/BannerShiftCore/Rules/RuleMatcher.swift`, change `compileForMatching` to translate
through `WildcardPattern` and update its doc comment:

```swift
  /// Compile `wildcard` into the `Regex` the matcher uses at runtime.
  ///
  /// The pattern is a BannerShift wildcard (`*` = any run, everything else
  /// literal), translated via `WildcardPattern` and compiled with `ignoresCase`
  /// + `dotMatchesNewlines`. Exposed so a future match-equivalence test can
  /// compile against the same semantics the matcher uses.
  public static func compileForMatching(_ wildcard: String) throws -> Regex<AnyRegexOutput> {
    try Regex(WildcardPattern.regexPattern(from: wildcard)).ignoresCase().dotMatchesNewlines()
  }
```

- [ ] **Step 4: Rewrite `matches` for empty-matches-nothing + AND**

Replace the `matches(_:_:)` method with:

```swift
  private func matches(_ rule: Rule, _ banner: BannerText) throws -> Bool {
    let criteria: [(pattern: String?, subject: String)] = [
      (rule.appPattern, banner.appName),
      (rule.bundleIDPattern, banner.bundleID ?? ""),
      (rule.titlePattern, banner.title),
      (rule.subtitlePattern, banner.subtitle),
      (rule.bodyPattern, banner.body),
    ]
    // A rule with no criteria specified matches nothing (not everything).
    let specified = criteria.filter { $0.pattern?.isEmpty == false }
    guard !specified.isEmpty else { return false }
    for criterion in specified {
      if try !check(criterion.pattern, criterion.subject) { return false }
    }
    return true
  }
```

The existing private `check(_:_:)` is unchanged: it still early-returns `true` for an
empty/nil pattern (now unreachable since `specified` excludes them) and otherwise compiles via
`compiledRegex` → `compileForMatching` and substring-matches with `firstMatch`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter RuleMatcher 2>&1 | tail -30`
Expected: PASS (all RuleMatcher tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/BannerShiftCore/Rules/RuleMatcher.swift Tests/BannerShiftCoreTests/Rules/RuleMatcherTests.swift
git commit -m "Match rules by wildcard; empty rule matches nothing"
```

---

### Task 3: Update the `Rule` doc comment (Core)

**Files:**
- Modify: `Sources/BannerShiftCore/Rules/Rule.swift`

- [ ] **Step 1: Update the type doc comment**

Replace the `Rule` type doc comment (the block immediately above `public struct Rule`) with:

```swift
/// One user-defined rule: a conjunction of wildcard patterns over banner
/// metadata plus an override position and animation to apply on match.
///
/// Pattern fields are simple wildcards, not regex: `*` matches any run of
/// characters and every other character is matched literally. Matching is
/// case-insensitive and substring-based (the pattern need only appear within
/// the field). An empty or nil pattern field is *ignored*; a rule with no
/// pattern fields specified matches nothing. Specified fields are combined
/// with logical AND. `position` and `animation` are optional so the editor can
/// leave them nil to mean "keep the default."
```

- [ ] **Step 2: Build to confirm it still compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShiftCore/Rules/Rule.swift
git commit -m "Document Rule's wildcard and empty-rule semantics"
```

---

### Task 4: Rewrite the edit sheet (wildcards, choosers, sections)

**Files:**
- Modify (full rewrite): `Sources/BannerShift/UI/RuleEditSheetController.swift`

No unit tests (executable target); verify by building the dev app and screenshotting the sheet.

- [ ] **Step 1: Replace the file contents**

Replace the full contents of `Sources/BannerShift/UI/RuleEditSheetController.swift` with:

```swift
import AppKit
import BannerShiftCore
import UniformTypeIdentifiers

/// Modal sheet for adding or editing a single rule.
///
/// Presented by `RuleEditorWindowController` over its window. Round-trips a
/// `Rule` by value: the caller hands in the rule to edit (or a fresh one for
/// "add") and the completion delivers the edited rule on Done, or `nil` on
/// Cancel. Fields are wildcard patterns (`*` = any run, everything else
/// literal), so there is nothing to validate — Done is always enabled. The
/// App and Bundle ID rows offer a Choose… button that fills the field from an
/// installed app picked via `NSOpenPanel`. The form is split into a Match
/// section (the criteria) and an Action section (position and animation).
/// AppKit, main-thread only.
final class RuleEditSheetController: NSObject {
  private let rule: Rule
  private let isNew: Bool
  private let completion: (Rule?) -> Void
  private var sheet: NSWindow?

  private let nameField = NSTextField()
  private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
  private let appField = NSTextField()
  private let bundleField = NSTextField()
  private let titleField = NSTextField()
  private let subtitleField = NSTextField()
  private let bodyField = NSTextField()
  private let positionPopUp = NSPopUpButton()
  private let animationPopUp = NSPopUpButton()
  private let doneButton = NSButton()

  /// - Parameters:
  ///   - rule: The rule to edit; pass a fresh `Rule` for "add". Its `id` is
  ///     preserved so an edit replaces the right rule in the store.
  ///   - isNew: Drives the header text and the confirm button title.
  ///   - completion: Called once when the sheet closes — the edited rule on
  ///     Done, `nil` on Cancel.
  init(rule: Rule, isNew: Bool, completion: @escaping (Rule?) -> Void) {
    self.rule = rule
    self.isNew = isNew
    self.completion = completion
    super.init()
  }

  /// Build and present the sheet over `parent`.
  func present(over parent: NSWindow) {
    let sheet = buildSheet()
    self.sheet = sheet
    loadFields()
    parent.beginSheet(sheet) { [weak self] response in
      guard let self else { return }
      self.completion(response == .OK ? self.collectRule() : nil)
      self.sheet = nil
    }
  }

  // MARK: UI

  private func buildSheet() -> NSWindow {
    nameField.placeholderString = "Rule name"
    for field in [appField, bundleField, titleField, subtitleField, bodyField] {
      field.placeholderString = "* matches anything; empty = ignore"
    }
    positionPopUp.addItem(withTitle: "(default)")
    Position.allCases.forEach { positionPopUp.addItem(withTitle: $0.displayName) }
    animationPopUp.addItem(withTitle: "(default)")
    Animation.allCases.forEach { animationPopUp.addItem(withTitle: $0.displayName) }

    let header = NSTextField(labelWithString: isNew ? "Add Rule" : "Edit Rule")
    header.font = .boldSystemFont(ofSize: 13)
    header.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let matchHeader = sectionLabel("Match")
    let actionHeader = sectionLabel("Action")
    let divider = NSBox()
    divider.boxType = .separator

    let appCell = fieldWithChooser(appField, chooserButton(#selector(chooseApp)))
    let bundleCell = fieldWithChooser(bundleField, chooserButton(#selector(chooseBundle)))

    let grid = NSGridView(views: [
      [rightLabel("Name:"), nameField],
      [NSGridCell.emptyContentView, enabledButton],
      [matchHeader, NSGridCell.emptyContentView],
      [rightLabel("App:"), appCell],
      [rightLabel("Bundle ID:"), bundleCell],
      [rightLabel("Title:"), titleField],
      [rightLabel("Subtitle:"), subtitleField],
      [rightLabel("Body:"), bodyField],
      [divider, NSGridCell.emptyContentView],
      [actionHeader, NSGridCell.emptyContentView],
      [rightLabel("Position:"), positionPopUp],
      [rightLabel("Animation:"), animationPopUp],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
    grid.rowSpacing = 8
    grid.columnSpacing = 8
    // Section headers and the divider span both columns.
    for rowIndex in [2, 8, 9] {
      grid.mergeCells(
        inHorizontalRange: NSRange(location: 0, length: 2),
        verticalRange: NSRange(location: rowIndex, length: 1))
    }
    grid.cell(for: matchHeader)?.xPlacement = .leading
    grid.cell(for: actionHeader)?.xPlacement = .leading
    grid.cell(for: divider)?.xPlacement = .fill
    grid.cell(for: positionPopUp)?.xPlacement = .leading
    grid.cell(for: animationPopUp)?.xPlacement = .leading
    grid.row(at: 2).topPadding = 6
    grid.row(at: 9).topPadding = 6
    // Field column hugs low so it absorbs the grid's slack; labels stay tight.
    for view in [nameField, appField, bundleField, titleField, subtitleField, bodyField]
      + [positionPopUp, animationPopUp] as [NSView]
    {
      view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1b}"
    doneButton.title = isNew ? "Add" : "Done"
    doneButton.bezelStyle = .rounded
    doneButton.keyEquivalent = "\r"
    doneButton.target = self
    doneButton.action = #selector(done)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let buttons = NSStackView(views: [spacer, cancelButton, doneButton])
    buttons.orientation = .horizontal
    buttons.spacing = 8

    let inset: CGFloat = 20
    let outer = NSStackView(views: [header, grid, buttons])
    outer.orientation = .vertical
    outer.alignment = .leading
    outer.spacing = 14
    outer.edgeInsets = NSEdgeInsets(top: 18, left: inset, bottom: 18, right: inset)
    outer.translatesAutoresizingMaskIntoConstraints = false

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
      styleMask: [.titled], backing: .buffered, defer: false)
    guard let content = window.contentView else { return window }
    content.addSubview(outer)
    NSLayoutConstraint.activate([
      outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      outer.topAnchor.constraint(equalTo: content.topAnchor),
      outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      // Set the field column width via a bare field; the App/Bundle cells share
      // that width with their Choose… button. Buttons span the grid so the
      // default button lines up under the fields' right edge.
      titleField.widthAnchor.constraint(equalToConstant: 300),
      buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
    ])
    window.layoutIfNeeded()
    window.setContentSize(outer.fittingSize)
    return window
  }

  private func rightLabel(_ string: String) -> NSTextField {
    let label = NSTextField(labelWithString: string)
    label.alignment = .right
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    return label
  }

  private func sectionLabel(_ string: String) -> NSTextField {
    let label = NSTextField(labelWithString: string)
    label.font = .boldSystemFont(ofSize: 11)
    label.textColor = .secondaryLabelColor
    return label
  }

  private func chooserButton(_ action: Selector) -> NSButton {
    let button = NSButton(title: "Choose\u{2026}", target: self, action: action)
    button.bezelStyle = .rounded
    button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    return button
  }

  private func fieldWithChooser(_ field: NSTextField, _ button: NSButton) -> NSView {
    let stack = NSStackView(views: [field, button])
    stack.orientation = .horizontal
    stack.spacing = 6
    return stack
  }

  // MARK: Load / collect

  private func loadFields() {
    nameField.stringValue = rule.name
    enabledButton.state = rule.enabled ? .on : .off
    appField.stringValue = rule.appPattern ?? ""
    bundleField.stringValue = rule.bundleIDPattern ?? ""
    titleField.stringValue = rule.titlePattern ?? ""
    subtitleField.stringValue = rule.subtitlePattern ?? ""
    bodyField.stringValue = rule.bodyPattern ?? ""
    positionPopUp.selectItem(
      at: rule.position.flatMap { Position.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
    animationPopUp.selectItem(
      at: rule.animation.flatMap { Animation.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
  }

  /// Build the edited rule from the field values, preserving the original id.
  private func collectRule() -> Rule {
    let positionIndex = positionPopUp.indexOfSelectedItem
    let animationIndex = animationPopUp.indexOfSelectedItem
    return Rule(
      id: rule.id,
      name: nameField.stringValue,
      enabled: enabledButton.state == .on,
      appPattern: nilIfEmpty(appField.stringValue),
      bundleIDPattern: nilIfEmpty(bundleField.stringValue),
      titlePattern: nilIfEmpty(titleField.stringValue),
      subtitlePattern: nilIfEmpty(subtitleField.stringValue),
      bodyPattern: nilIfEmpty(bodyField.stringValue),
      position: positionIndex == 0 ? nil : Position.allCases[positionIndex - 1],
      animation: animationIndex == 0 ? nil : Animation.allCases[animationIndex - 1]
    )
  }

  private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

  // MARK: App chooser

  @objc private func chooseApp() {
    chooseApplication { [weak self] url in
      self?.appField.stringValue = FileManager.default.displayName(atPath: url.path)
    }
  }

  @objc private func chooseBundle() {
    chooseApplication { [weak self] url in
      if let identifier = Bundle(url: url)?.bundleIdentifier {
        self?.bundleField.stringValue = identifier
      }
    }
  }

  /// Present an app picker over the sheet and pass the chosen `.app` URL to
  /// `assign`. No-op if the user cancels.
  private func chooseApplication(_ assign: @escaping (URL) -> Void) {
    guard let sheet else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = "Choose"
    panel.beginSheetModal(for: sheet) { response in
      guard response == .OK, let url = panel.url else { return }
      assign(url)
    }
  }

  // MARK: Actions

  @objc private func done() {
    guard let sheet else { return }
    sheet.sheetParent?.endSheet(sheet, returnCode: .OK)
  }

  @objc private func cancel() {
    guard let sheet else { return }
    sheet.sheetParent?.endSheet(sheet, returnCode: .cancel)
  }
}
```

- [ ] **Step 2: Build the dev app**

Run: `make dev 2>&1 | tail -3`
Expected: `done: .../build/BannerShift.app` (the temporary auto-show + seed scaffolding in
`AppDelegate` opens the rules window on launch).

- [ ] **Step 3: Open the edit sheet and screenshot it**

```bash
pkill -x BannerShift 2>/dev/null; sleep 1
open /Users/ryanemerle/repos/personal/BannerShift/build/BannerShift.app; sleep 2.5
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "BannerShift") to true'
osascript -e 'tell application "System Events" to tell process "BannerShift" to click (first button of window 1 whose description is "Add rule")'
sleep 0.8
WID=$(swift /tmp/bannershift-ui/winid.swift | awk -F'\t' '$2=="" && $3 ~ /Width.: 4/ {print $1}')
screencapture -o -l "$WID" /tmp/bannershift-ui/edit-sections.png
```

Then Read `/tmp/bannershift-ui/edit-sections.png`.
Expected: a "Match" section header above App/Bundle/Title/Subtitle/Body, a divider, an
"Action" header above Position/Animation; Choose… buttons trailing the App and Bundle ID
fields; placeholder text `* matches anything; empty = ignore`. Adjust spacing/widths and
re-screenshot until it reads cleanly.

- [ ] **Step 4: Verify the chooser works**

Click a Choose… button (`osascript … click (first button of window 1 whose title is "Choose…")`),
pick an app in the panel, confirm the field fills (App → display name, Bundle ID → identifier).

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShift/UI/RuleEditSheetController.swift
git commit -m "Rule edit sheet: wildcards, app chooser, Match/Action sections"
```

---

### Task 5: Fix the temp seed and update the changelog

**Files:**
- Modify: `Sources/BannerShift/App/AppDelegate.swift`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Fix the seed's bundle pattern to wildcard form**

In `Sources/BannerShift/App/AppDelegate.swift`, in the temporary seed block, change the Mail
rule's bundle pattern from regex-escaped to wildcard form:

```swift
        Rule(
          name: "Mail", enabled: false, bundleIDPattern: "com.apple.mail",
          position: .bottomRight, animation: .bounce),
```

- [ ] **Step 2: Add changelog entries**

In `CHANGELOG.md`, under `## [Unreleased]`, add to `### Changed`:

```markdown
- Rule fields now use simple wildcards (`*` matches any run of characters;
  everything else is literal) instead of regular expressions. A rule with no
  criteria specified now matches nothing rather than every notification, and
  multiple specified fields are combined with AND.
```

and add an `### Added` group (place it before `### Changed`) with:

```markdown
### Added

- Choose… buttons on the App and Bundle ID fields in the rule editor to pick an
  installed app instead of typing its name or identifier.
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/BannerShift/App/AppDelegate.swift CHANGELOG.md
git commit -m "Use wildcard seed pattern; changelog for wildcard rules"
```

---

### Task 6: Remove iteration scaffolding and validate

**Files:**
- Modify: `Sources/BannerShift/App/AppDelegate.swift`

- [ ] **Step 1: Remove the temporary scaffolding**

In `Sources/BannerShift/App/AppDelegate.swift`, delete the two `TEMP(ui-iteration)` blocks:
the sample-rule seeding block (before `RuleEditorWindowController(ruleStore:)`) and the
`ruleEditor.show()` call at the end of `applicationDidFinishLaunching`.

- [ ] **Step 2: Run the full gate**

Run: `make validate 2>&1 | tail -6`
Expected: `validate: all checks ok` (lint clean, build complete, all tests pass including the
new WildcardPattern and updated RuleMatcher tests).

- [ ] **Step 3: Manual smoke test**

Run: `make dev` then `open build/BannerShift.app`. Open the rules editor from the menu bar,
add a rule with App `Slack`, send a Slack-style test notification, and confirm it repositions;
confirm an empty rule (no fields) does nothing.

- [ ] **Step 4: Commit**

```bash
git add Sources/BannerShift/App/AppDelegate.swift
git commit -m "Remove rule-editor UI iteration scaffolding"
```

---

## Self-Review

**Spec coverage:**
- Wildcard `*`→`.*`, literal everything else, substring → Task 1 (`WildcardPattern`) + Task 2 (`compileForMatching` translates, unanchored `firstMatch`). ✓
- Empty field ignored; no fields → matches nothing; AND → Task 2 (`matches` rewrite). ✓
- `Rule` doc update → Task 3. ✓
- Wildcard placeholders + remove validation → Task 4. ✓
- App/Bundle ID Choose… via NSOpenPanel → Task 4. ✓
- Matcher/action separation → Task 4 (Match/Action sections). ✓
- No migration, no new entitlement → nothing to do (NSOpenPanel needs none unsandboxed). ✓
- Test updates (rename catch-all, fix regex-flavored patterns, drop malformed tests) → Task 2. ✓
- Temp seed fix + changelog → Task 5. ✓

**Type consistency:** `WildcardPattern.regexPattern(from:)` used identically in Task 1 and Task 2's
`compileForMatching`. `RuleEditSheetController` keeps the `present(over:)`/`completion` interface
its caller (`RuleEditorWindowController.presentEditSheet`) already uses, so no caller change is
needed. `Rule` initializer argument order (`id, name, enabled, …Pattern, position, animation`)
matches Task 4's `collectRule` and Task 5's seed.

**Placeholder scan:** no TBD/TODO/"handle edge cases"; every code step shows complete code.
