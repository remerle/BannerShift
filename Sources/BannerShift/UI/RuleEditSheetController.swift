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
/// section (the criteria) and an Action section (animation and whether to
/// pin the banner to the always-on-top list). Position is global — set
/// from the menu bar's Default Position submenu — and not per-rule.
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
  private let animationPopUp = NSPopUpButton()
  private let pinButton = NSButton(
    checkboxWithTitle: "Also pin to the always-on-top list", target: nil, action: nil)
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
    let header = NSTextField(labelWithString: isNew ? "Add Rule" : "Edit Rule")
    header.font = .boldSystemFont(ofSize: 13)
    header.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let grid = makeGrid()
    let buttons = makeButtons()

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

  /// Build the configured form grid: a Match section (the criteria, with
  /// Choose… buttons on the App and Bundle ID rows) over an Action section
  /// (animation and pin), with right-aligned labels.
  private func makeGrid() -> NSGridView {
    nameField.placeholderString = "Rule name"
    for field in [appField, bundleField, titleField, subtitleField, bodyField] {
      field.placeholderString = "* matches anything; empty = ignore"
    }
    animationPopUp.addItem(withTitle: "(default)")
    for animation in Animation.allCases { animationPopUp.addItem(withTitle: animation.displayName) }

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
      [rightLabel("Animation:"), animationPopUp],
      [NSGridCell.emptyContentView, pinButton],
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
    grid.cell(for: animationPopUp)?.xPlacement = .leading
    grid.row(at: 2).topPadding = 6
    grid.row(at: 9).topPadding = 6
    // Field column hugs low so it absorbs the grid's slack; labels stay tight.
    for view in [nameField, appField, bundleField, titleField, subtitleField, bodyField]
      + [animationPopUp] as [NSView]
    {
      view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    return grid
  }

  /// Build the trailing Cancel/Add(Done) button row; a leading spacer pushes
  /// the buttons to the trailing edge.
  private func makeButtons() -> NSStackView {
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
    return buttons
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
    animationPopUp.selectItem(
      at: rule.animation.flatMap { Animation.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
    pinButton.state = rule.pinsToList ? .on : .off
  }

  /// Build the edited rule from the field values, preserving the original id.
  private func collectRule() -> Rule {
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
      pinsToList: pinButton.state == .on,
      animation: animationIndex == 0 ? nil : Animation.allCases[animationIndex - 1]
    )
  }

  private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }

  // MARK: App chooser

  @objc private func chooseApp() {
    chooseApplication { [weak self] url in
      self?.appField.stringValue = Self.notificationAppName(for: url)
    }
  }

  /// Best-effort reconstruction of the app name a macOS notification banner
  /// reports, used to pre-fill the App match field from a chosen `.app`.
  ///
  /// The banner header shows the app's *display* name, which the rule matcher
  /// sees as `BannerText.appName`. That is `CFBundleDisplayName` when present,
  /// otherwise `CFBundleName` — read from the localized Info dictionary first
  /// so a localized install pre-fills the string the user actually sees on
  /// screen. Falls back to the Finder display name (with any ".app" extension
  /// stripped) only when the bundle exposes neither key, since
  /// `FileManager.displayName(atPath:)` can diverge from the banner's name.
  private static func notificationAppName(for url: URL) -> String {
    if let bundle = Bundle(url: url) {
      for key in ["CFBundleDisplayName", "CFBundleName"] {
        if let name = (bundle.localizedInfoDictionary?[key] ?? bundle.infoDictionary?[key])
          as? String, !name.isEmpty
        {
          return name
        }
      }
    }
    let displayName = FileManager.default.displayName(atPath: url.path)
    return displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
  }

  @objc private func chooseBundle() {
    chooseApplication { [weak self] url in
      if let identifier = Bundle(url: url)?.bundleIdentifier {
        self?.bundleField.stringValue = identifier
      }
    }
  }

  /// Present an app picker over the sheet and pass the chosen `.app` URL to
  /// `assign`.
  ///
  /// No-op if the user cancels.
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
