import AppKit
import BannerShiftCore
import Foundation

/// Window controller for the rules editor: an idiomatic macOS list editor.
///
/// The window is just the rule list plus an action bar (`+` / `–` and
/// `Test…`). Adding a rule, or double-clicking an existing one, opens a
/// `RuleEditSheetController` sheet that round-trips a single `Rule`;
/// `Test…` opens a `RuleTestSheetController`. The store is written only when
/// a sheet returns a committed edit (or on add/remove/reorder/toggle), not on
/// every keystroke. AppKit, main-thread only.
final class RuleEditorWindowController: NSWindowController {
  private let ruleStore: RuleStore
  private var rules: [Rule] = []
  private var selectedIndex: Int? {
    tableView.selectedRow >= 0 ? tableView.selectedRow : nil
  }

  private let tableView = NSTableView()
  private let addButton = NSButton()
  private let removeButton = NSButton()
  private let testButton = NSButton()

  /// Retains the sheet controller while its sheet is on screen; the
  /// completion handler clears it.
  private var activeSheet: AnyObject?

  /// Create the editor window and load the current rules from the store.
  ///
  /// Builds the view hierarchy up front and retains the window
  /// (`isReleasedWhenClosed = false`) so the controller survives the user
  /// closing it and `show()` can reopen the same instance.
  init(ruleStore: RuleStore) {
    self.ruleStore = ruleStore
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 580, height: 400),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = "BannerShift Rules"
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    rules = ruleStore.load()
    buildUI()
    refreshTable()
    updateButtonState()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

  /// Bring the editor window to the front.
  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.bringToFront()
  }

  // MARK: UI

  private func buildUI() {
    guard let content = window?.contentView else { return }

    configureTable()
    let scroll = NSScrollView()
    scroll.documentView = tableView
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.autohidesScrollers = true

    configureFooterButton(addButton, symbol: "plus", help: "Add rule", action: #selector(addRule))
    configureFooterButton(
      removeButton, symbol: "minus", help: "Remove rule", action: #selector(removeRule))
    let listButtons = NSStackView(views: [addButton, removeButton])
    listButtons.orientation = .horizontal
    listButtons.spacing = -1  // butt the two buttons together like a segmented control

    testButton.title = "Test\u{2026}"
    testButton.bezelStyle = .rounded
    testButton.target = self
    testButton.action = #selector(testRules)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let actionBar = NSStackView(views: [listButtons, spacer, testButton])
    actionBar.orientation = .horizontal
    actionBar.alignment = .centerY
    actionBar.spacing = 8

    let outer = NSStackView(views: [scroll, actionBar])
    outer.orientation = .vertical
    outer.alignment = .width
    outer.spacing = 8
    outer.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    outer.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(outer)
    NSLayoutConstraint.activate([
      outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      outer.topAnchor.constraint(equalTo: content.topAnchor),
      outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
    ])
  }

  /// Style a small, icon-only `+`/`–` footer button in the macOS list-editor
  /// idiom (square bezel, no title), sized to sit flush beneath the table.
  private func configureFooterButton(
    _ button: NSButton, symbol: String, help: String, action: Selector
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
    button.imagePosition = .imageOnly
    button.bezelStyle = .smallSquare
    button.setButtonType(.momentaryPushIn)
    button.toolTip = help
    button.target = self
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 28),
      button.heightAnchor.constraint(equalToConstant: 22),
    ])
  }

  private struct ColumnSpec {
    let id: String
    let title: String
    let width: CGFloat
  }

  private func configureTable() {
    let cols: [ColumnSpec] = [
      ColumnSpec(id: "on", title: "On", width: 32),
      ColumnSpec(id: "name", title: "Name", width: 180),
      ColumnSpec(id: "app", title: "App", width: 130),
      ColumnSpec(id: "rule", title: "Position / Animation", width: 190),
    ]
    for spec in cols {
      let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
      col.title = spec.title
      col.width = spec.width
      tableView.addTableColumn(col)
    }
    tableView.dataSource = self
    tableView.delegate = self
    tableView.allowsEmptySelection = true
    tableView.allowsMultipleSelection = false
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    tableView.target = self
    tableView.doubleAction = #selector(editSelectedRule)
    tableView.registerForDraggedTypes([.string])
  }

  // MARK: Table state

  private func refreshTable() {
    tableView.reloadData()
    if let index = selectedIndex, rules.indices.contains(index) {
      tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    updateButtonState()
  }

  private func selectRow(_ index: Int) {
    guard rules.indices.contains(index) else { return }
    tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    updateButtonState()
  }

  private func updateButtonState() {
    removeButton.isEnabled = selectedIndex != nil
    testButton.isEnabled = !rules.isEmpty
  }

  // MARK: Actions

  @objc private func addRule() {
    presentEditSheet(for: Rule(name: "New Rule"), isNew: true) { [weak self] edited in
      guard let self else { return }
      self.rules.append(edited)
      self.ruleStore.save(self.rules)
      self.refreshTable()
      self.selectRow(self.rules.count - 1)
    }
  }

  @objc private func removeRule() {
    guard let index = selectedIndex, rules.indices.contains(index) else { return }
    rules.remove(at: index)
    ruleStore.save(rules)
    refreshTable()
    if !rules.isEmpty { selectRow(min(index, rules.count - 1)) }
  }

  @objc private func editSelectedRule() {
    guard let index = selectedIndex, rules.indices.contains(index) else { return }
    presentEditSheet(for: rules[index], isNew: false) { [weak self] edited in
      guard let self, let row = self.rules.firstIndex(where: { $0.id == edited.id }) else { return }
      self.rules[row] = edited
      self.ruleStore.save(self.rules)
      self.refreshTable()
      self.selectRow(row)
    }
  }

  @objc private func testRules() {
    guard let window else { return }
    let controller = RuleTestSheetController(rules: rules)
    activeSheet = controller
    controller.present(over: window)
  }

  /// Present the add/edit sheet and invoke `onCommit` only if the user
  /// confirmed (the sheet returned an edited rule).
  private func presentEditSheet(for rule: Rule, isNew: Bool, onCommit: @escaping (Rule) -> Void) {
    guard let window else { return }
    let controller = RuleEditSheetController(rule: rule, isNew: isNew) { [weak self] edited in
      self?.activeSheet = nil
      if let edited { onCommit(edited) }
    }
    activeSheet = controller
    controller.present(over: window)
  }
}

// MARK: NSTableViewDataSource

extension RuleEditorWindowController: NSTableViewDataSource {
  func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

  /// Drag-to-reorder: make a row draggable, carrying its index as the
  /// pasteboard payload.
  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
    let item = NSPasteboardItem()
    item.setString("\(row)", forType: .string)
    return item
  }

  /// Drag-to-reorder: allow the drop only as an insertion between rows
  /// (`.above`), presented as a move.
  func tableView(
    _ tableView: NSTableView,
    validateDrop info: NSDraggingInfo,
    proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
  ) -> NSDragOperation {
    dropOperation == .above ? .move : []
  }

  /// Drag-to-reorder: move the dragged rule to the drop location, persist
  /// the new order, and keep the moved rule selected.
  func tableView(
    _ tableView: NSTableView,
    acceptDrop info: NSDraggingInfo,
    row: Int,
    dropOperation: NSTableView.DropOperation
  ) -> Bool {
    guard let item = info.draggingPasteboard.pasteboardItems?.first,
      let payload = item.string(forType: .string),
      let src = Int(payload),
      rules.indices.contains(src)
    else { return false }
    let dst = src < row ? row - 1 : row
    let moved = rules.remove(at: src)
    let insertAt = min(dst, rules.count)
    rules.insert(moved, at: insertAt)
    ruleStore.save(rules)
    refreshTable()
    selectRow(insertAt)
    return true
  }
}

// MARK: NSTableViewDelegate

extension RuleEditorWindowController: NSTableViewDelegate {
  /// Build the cell view for a column: an enabled checkbox for "on", plain
  /// labels for name/app, and a "position / animation" summary for "rule".
  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    guard let id = tableColumn?.identifier.rawValue else { return nil }
    let rule = rules[row]
    switch id {
    case "on":
      let button = NSButton(
        checkboxWithTitle: "", target: self, action: #selector(rowEnabledToggled(_:)))
      button.state = rule.enabled ? .on : .off
      button.tag = row
      return button

    case "name":
      return NSTextField(labelWithString: rule.name)

    case "app":
      // Fall back to the bundle-ID pattern so a rule that targets a source
      // only by bundle ID (no app pattern) doesn't misleadingly read as "(any)".
      let source = rule.appPattern ?? rule.bundleIDPattern ?? "(any)"
      return NSTextField(labelWithString: source)

    case "rule":
      let position = rule.position?.displayName ?? "default"
      let animation = rule.animation?.displayName ?? "default"
      return NSTextField(labelWithString: "\(position) / \(animation)")

    default:
      return nil
    }
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateButtonState()
  }

  @objc private func rowEnabledToggled(_ sender: NSButton) {
    let row = sender.tag
    guard rules.indices.contains(row) else { return }
    rules[row].enabled = sender.state == .on
    ruleStore.save(rules)
  }
}
