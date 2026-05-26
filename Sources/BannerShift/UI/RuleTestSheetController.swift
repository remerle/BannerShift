import AppKit
import BannerShiftCore

/// Modal sheet that tests sample banner text against the current rule set.
///
/// Presented by `RuleEditorWindowController` over its window. Holds a
/// snapshot of the rules taken at present time and its own `RuleMatcher`;
/// as the user types sample fields it reports which rule matches *first*
/// (the same precedence the live mover uses), or that none match. Read-only:
/// it never mutates the store. AppKit, main-thread only.
final class RuleTestSheetController: NSObject, NSTextFieldDelegate {
  private let rules: [Rule]
  private let matcher = RuleMatcher()
  private var sheet: NSWindow?

  private let appField = NSTextField()
  private let bundleField = NSTextField()
  private let titleField = NSTextField()
  private let subtitleField = NSTextField()
  private let bodyField = NSTextField()
  private let resultLabel = NSTextField(labelWithString: "No rule matches.")

  /// - Parameter rules: Snapshot of the rules to test against, in priority
  ///   order.
  init(rules: [Rule]) {
    self.rules = rules
    super.init()
  }

  /// Build and present the sheet over `parent`.
  func present(over parent: NSWindow) {
    let sheet = buildSheet()
    self.sheet = sheet
    updateResult()
    parent.beginSheet(sheet) { [weak self] _ in self?.sheet = nil }
  }

  // MARK: UI

  private func buildSheet() -> NSWindow {
    let header = NSTextField(labelWithString: "Test a Rule")
    header.font = .boldSystemFont(ofSize: 13)
    // Low hugging so the `.width`-aligned outer stack stretches the label to
    // full width; otherwise it keeps its intrinsic width and lands trailing.
    header.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let subtitle = NSTextField(
      labelWithString: "Type sample banner text to see which rule matches first.")
    subtitle.font = .systemFont(ofSize: 11)
    subtitle.textColor = .secondaryLabelColor
    subtitle.setContentHuggingPriority(.defaultLow, for: .horizontal)

    for field in [appField, bundleField, titleField, subtitleField, bodyField] {
      field.delegate = self
    }

    let grid = NSGridView(views: [
      [rightLabel("App:"), appField],
      [rightLabel("Bundle ID:"), bundleField],
      [rightLabel("Title:"), titleField],
      [rightLabel("Subtitle:"), subtitleField],
      [rightLabel("Body:"), bodyField],
    ])
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
    grid.rowSpacing = 8
    grid.columnSpacing = 8
    for field in [appField, bundleField, titleField, subtitleField, bodyField] {
      field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    let resultBox = NSBox()
    resultBox.boxType = .separator

    let footer = makeFooter()

    let inset: CGFloat = 20
    let outer = NSStackView(views: [header, subtitle, grid, resultBox, footer])
    outer.orientation = .vertical
    outer.alignment = .leading
    outer.spacing = 12
    outer.setCustomSpacing(4, after: header)
    outer.edgeInsets = NSEdgeInsets(top: 18, left: inset, bottom: 18, right: inset)
    outer.translatesAutoresizingMaskIntoConstraints = false

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
      styleMask: [.titled], backing: .buffered, defer: false)
    guard let content = window.contentView else { return window }
    content.addSubview(outer)
    NSLayoutConstraint.activate([
      outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      outer.topAnchor.constraint(equalTo: content.topAnchor),
      outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      // Give the field column a usable width; the grid then sizes naturally.
      // The header, subtitle, separator, and footer span the grid so they
      // share its left and right edges.
      appField.widthAnchor.constraint(equalToConstant: 300),
      header.widthAnchor.constraint(equalTo: grid.widthAnchor),
      subtitle.widthAnchor.constraint(equalTo: grid.widthAnchor),
      resultBox.widthAnchor.constraint(equalTo: grid.widthAnchor),
      footer.widthAnchor.constraint(equalTo: grid.widthAnchor),
    ])
    // Shrink the sheet to fit the form so there is no empty margin.
    window.layoutIfNeeded()
    window.setContentSize(outer.fittingSize)
    return window
  }

  /// The result label and the Done button, with a flexible spacer pushing
  /// Done to the trailing edge (a low-hugging label alone does not reliably
  /// absorb the row's slack; this matches the edit sheet footer).
  private func makeFooter() -> NSStackView {
    let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
    doneButton.bezelStyle = .rounded
    doneButton.keyEquivalent = "\r"
    resultLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let footer = NSStackView(views: [resultLabel, spacer, doneButton])
    footer.orientation = .horizontal
    footer.spacing = 8
    return footer
  }

  private func rightLabel(_ string: String) -> NSTextField {
    let label = NSTextField(labelWithString: string)
    label.alignment = .right
    // Hug tightly so the label column stays at its content width and the grid's
    // extra width flows to the (low-hugging) field column instead.
    label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    return label
  }

  // MARK: Matching

  private func updateResult() {
    // Mirror the live mover's precedence: it resolves the bundle ID from the
    // app's display name via `AppResolver` before matching
    // (`BannerMover.resolveAnimationAndPin`). Do the same here so a
    // `bundleIDPattern` rule tested by app name behaves identically to
    // production. An explicitly typed bundle ID still wins.
    let appName = appField.stringValue
    let bundleID = nilIfEmpty(bundleField.stringValue) ?? AppResolver.bundleID(forAppName: appName)
    let banner = BannerText(
      appName: appName,
      bundleID: bundleID,
      title: titleField.stringValue,
      subtitle: subtitleField.stringValue,
      body: bodyField.stringValue
    )
    if let match = matcher.match(rules: rules, banner: banner) {
      resultLabel.stringValue = "Match: \(match.rule.name)"
      resultLabel.textColor = .systemGreen
    } else {
      resultLabel.stringValue = "No rule matches."
      resultLabel.textColor = .secondaryLabelColor
    }
  }

  private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

  func controlTextDidChange(_ obj: Notification) {
    updateResult()
  }

  @objc private func done() {
    guard let sheet else { return }
    sheet.sheetParent?.endSheet(sheet, returnCode: .OK)
  }
}
