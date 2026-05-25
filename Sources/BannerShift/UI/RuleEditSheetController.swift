import AppKit
import BannerShiftCore

/// Modal sheet for adding or editing a single rule.
///
/// Presented by `RuleEditorWindowController` over its window. Round-trips a
/// `Rule` by value: the caller hands in the rule to edit (or a fresh one for
/// "add") and the completion delivers the edited rule on Done, or `nil` on
/// Cancel — so the caller commits to the store only on Done. Regex fields are
/// validated live with `RuleMatcher.compileForMatching`; Done is disabled
/// while any pattern is invalid, so a bad rule can never be saved. AppKit,
/// main-thread only.
final class RuleEditSheetController: NSObject, NSTextFieldDelegate {
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
  private let statusLabel = NSTextField(labelWithString: "")
  private let doneButton = NSButton()

  /// The regex-backed fields paired with the label used in error messages.
  private var regexFields: [(field: NSTextField, name: String)] {
    [
      (appField, "App"), (bundleField, "Bundle ID"), (titleField, "Title"),
      (subtitleField, "Subtitle"), (bodyField, "Body"),
    ]
  }

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
    validate()
    parent.beginSheet(sheet) { [weak self] response in
      guard let self else { return }
      self.completion(response == .OK ? self.collectRule() : nil)
      self.sheet = nil
    }
  }

  // MARK: UI

  private func buildSheet() -> NSWindow {
    nameField.placeholderString = "Rule name"
    nameField.delegate = self
    for (field, _) in regexFields {
      field.delegate = self
      field.placeholderString = "regex (empty = matches anything)"
    }
    positionPopUp.addItem(withTitle: "(default)")
    for position in Position.allCases { positionPopUp.addItem(withTitle: position.displayName) }
    animationPopUp.addItem(withTitle: "(default)")
    for animation in Animation.allCases { animationPopUp.addItem(withTitle: animation.displayName) }

    let header = NSTextField(labelWithString: isNew ? "Add Rule" : "Edit Rule")
    header.font = .boldSystemFont(ofSize: 13)
    // Low hugging so the `.width`-aligned outer stack stretches the label to
    // full width; otherwise it keeps its intrinsic width and lands trailing.
    header.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let grid = NSGridView(views: [
      [rightLabel("Name:"), nameField],
      [NSGridCell.emptyContentView, enabledButton],
      [rightLabel("App:"), appField],
      [rightLabel("Bundle ID:"), bundleField],
      [rightLabel("Title:"), titleField],
      [rightLabel("Subtitle:"), subtitleField],
      [rightLabel("Body:"), bodyField],
      [rightLabel("Position:"), positionPopUp],
      [rightLabel("Animation:"), animationPopUp],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
    grid.rowSpacing = 8
    grid.columnSpacing = 8
    // Popups read better at their natural width than stretched across the cell.
    grid.cell(for: positionPopUp)?.xPlacement = .leading
    grid.cell(for: animationPopUp)?.xPlacement = .leading
    // Everything in the field column hugs low so the column absorbs the grid's
    // slack and the labels stay tight. The popups keep their natural width via
    // the `.leading` cell placement above despite the low hugging.
    for view in [nameField, appField, bundleField, titleField, subtitleField, bodyField]
      + [positionPopUp, animationPopUp] as [NSView]
    {
      view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    let buttons = makeFooter()

    let inset: CGFloat = 20
    let outer = NSStackView(views: [header, grid, buttons])
    outer.orientation = .vertical
    outer.alignment = .leading
    outer.spacing = 14
    outer.edgeInsets = NSEdgeInsets(top: 18, left: inset, bottom: 18, right: inset)
    outer.translatesAutoresizingMaskIntoConstraints = false

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 430),
      styleMask: [.titled], backing: .buffered, defer: false)
    guard let content = window.contentView else { return window }
    content.addSubview(outer)
    NSLayoutConstraint.activate([
      outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      outer.topAnchor.constraint(equalTo: content.topAnchor),
      outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      // Give the field column a usable width. The grid then sizes naturally
      // (label column hugs its text); forcing the grid wider only made
      // NSGridView park the slack in the label column. The button row spans
      // the grid so the default button lines up under the fields' right edge.
      nameField.widthAnchor.constraint(equalToConstant: 300),
      buttons.widthAnchor.constraint(equalTo: grid.widthAnchor),
    ])
    // Shrink the sheet to fit the form so there is no empty margin.
    window.layoutIfNeeded()
    window.setContentSize(outer.fittingSize)
    return window
  }

  /// The error/status label plus Cancel and Done buttons.
  ///
  /// A bare spacer (not the status label) is the flexible element that pushes
  /// Cancel/Done to the trailing edge; the stack's default gravity layout does
  /// not stretch a text field on its own.
  private func makeFooter() -> NSStackView {
    statusLabel.textColor = .systemRed
    statusLabel.font = .systemFont(ofSize: 11)
    statusLabel.lineBreakMode = .byTruncatingTail

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
    let buttons = NSStackView(views: [statusLabel, spacer, cancelButton, doneButton])
    buttons.orientation = .horizontal
    buttons.spacing = 8
    return buttons
  }

  private func rightLabel(_ string: String) -> NSTextField {
    let label = NSTextField(labelWithString: string)
    label.alignment = .right
    // Hug tightly so the label column stays at its content width and the grid's
    // extra width flows to the (low-hugging) field column instead.
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    return label
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

  // MARK: Validation

  /// Re-validate every regex field, flag the invalid ones, and gate Done.
  ///
  /// Compiles with the same option set the runtime matcher applies so a
  /// pattern that would behave differently at runtime than under a bare
  /// `Regex(pattern)` is still caught here.
  private func validate() {
    var firstError: String?
    for (field, name) in regexFields {
      field.wantsLayer = true
      let pattern = field.stringValue
      if pattern.isEmpty {
        field.layer?.borderWidth = 0
        continue
      }
      do {
        _ = try RuleMatcher.compileForMatching(pattern)
        field.layer?.borderWidth = 0
      } catch {
        field.layer?.borderColor = NSColor.systemRed.cgColor
        field.layer?.borderWidth = 1
        field.layer?.cornerRadius = 4
        if firstError == nil { firstError = "\(name): invalid regex" }
      }
    }
    statusLabel.stringValue = firstError ?? ""
    doneButton.isEnabled = firstError == nil
  }

  func controlTextDidChange(_ obj: Notification) {
    validate()
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
