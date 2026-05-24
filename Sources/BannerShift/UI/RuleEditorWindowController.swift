import AppKit
import BannerShiftCore
import Foundation

/// Window controller for the rules editor: a master/detail list of rules
/// plus a live "test against sample text" pane.
///
/// Edits write straight back to the `RuleStore` on every change (there is
/// no explicit Save button), and regex fields are validated against
/// `RuleMatcher.compileForMatching` as you type so an invalid pattern is
/// flagged before it can reach the matcher. Holds its own `RuleMatcher`
/// solely to power the sample tester. AppKit, main-thread only.
final class RuleEditorWindowController: NSWindowController {
  private let ruleStore: RuleStore
  private let matcher = RuleMatcher()
  private var rules: [Rule] = []
  private var selectedIndex: Int?

  // List pane
  private let tableView = NSTableView()
  private let addButton = NSButton()
  private let removeButton = NSButton()

  // Detail pane controls
  private let nameField = NSTextField()
  private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
  private let appField = NSTextField()
  private let bundleField = NSTextField()
  private let titleField = NSTextField()
  private let subtitleField = NSTextField()
  private let bodyField = NSTextField()
  private let appError = NSTextField(labelWithString: "")
  private let bundleError = NSTextField(labelWithString: "")
  private let titleError = NSTextField(labelWithString: "")
  private let subtitleError = NSTextField(labelWithString: "")
  private let bodyError = NSTextField(labelWithString: "")
  private let positionPopUp = NSPopUpButton()
  private let animationPopUp = NSPopUpButton()

  // Sample tester
  private let sampleAppField = NSTextField()
  private let sampleBundleField = NSTextField()
  private let sampleTitleField = NSTextField()
  private let sampleSubtitleField = NSTextField()
  private let sampleBodyField = NSTextField()
  private let testResultLabel = NSTextField(labelWithString: "No rule matches.")

  /// Create the editor window and load the current rules from the store.
  ///
  /// Builds the whole view hierarchy up front and retains the window
  /// (`isReleasedWhenClosed = false`), so the controller survives the user
  /// closing it and `show()` can reopen the same instance.
  init(ruleStore: RuleStore) {
    self.ruleStore = ruleStore
    let frame = NSRect(x: 0, y: 0, width: 760, height: 560)
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    window.title = "BannerShift Rules"
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    rules = ruleStore.load()
    buildUI()
    refreshTable()
    loadDetailForSelection()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

  /// Bring the editor window to the front.
  ///
  /// The window itself is built at init, so this creates nothing.
  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.bringToFront()
  }

  // MARK: UI

  private func buildUI() {
    guard let content = window?.contentView else { return }

    configureTable()
    configureListButton(addButton, symbol: "plus", accessibility: "Add rule", action: #selector(addRule))
    configureListButton(
      removeButton, symbol: "minus", accessibility: "Remove rule", action: #selector(removeRule))
    let listButtons = NSStackView(views: [addButton, removeButton])
    listButtons.orientation = .horizontal
    listButtons.spacing = 0
    let scroll = NSScrollView()
    scroll.documentView = tableView
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    let leftStack = NSStackView(views: [scroll, listButtons])
    leftStack.orientation = .vertical
    leftStack.alignment = .leading
    leftStack.spacing = 6

    let detail = makeDetailForm()

    let top = NSStackView(views: [leftStack, detail])
    top.orientation = .horizontal
    top.distribution = .fillEqually
    top.spacing = 16

    let separator = NSBox()
    separator.boxType = .separator

    let bottom = makeTester()

    let outer = NSStackView(views: [top, separator, bottom])
    outer.orientation = .vertical
    // Stretch every section to the full content width; with `.leading` the
    // tester row collapsed to its fields' intrinsic widths and truncated.
    outer.alignment = .width
    outer.spacing = 12
    outer.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    outer.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(outer)
    NSLayoutConstraint.activate([
      outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      outer.topAnchor.constraint(equalTo: content.topAnchor),
      outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
    ])
  }

  /// Style a small, icon-only `+`/`-` footer button in the macOS list-editor
  /// idiom (square bezel, no title), sized to sit flush beneath the table.
  private func configureListButton(
    _ button: NSButton, symbol: String, accessibility: String, action: Selector
  ) {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
    button.imagePosition = .imageOnly
    button.bezelStyle = .smallSquare
    button.setButtonType(.momentaryPushIn)
    button.target = self
    button.action = action
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 28),
      button.heightAnchor.constraint(equalToConstant: 24),
    ])
  }

  private struct ColumnSpec {
    let id: String
    let title: String
    let width: CGFloat
  }

  private func configureTable() {
    let cols: [ColumnSpec] = [
      ColumnSpec(id: "on", title: "On", width: 40),
      ColumnSpec(id: "name", title: "Name", width: 140),
      ColumnSpec(id: "app", title: "App", width: 100),
      ColumnSpec(id: "rule", title: "Pos / Anim", width: 120),
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
    tableView.target = self
    tableView.action = #selector(tableSelectionChanged(_:))
    tableView.registerForDraggedTypes([.string])
  }

  private func makeDetailForm() -> NSView {
    nameField.placeholderString = "Rule name"
    enabledButton.target = self
    enabledButton.action = #selector(detailChanged)
    nameField.delegate = self
    for tf in [appField, bundleField, titleField, subtitleField, bodyField] {
      tf.delegate = self
      tf.placeholderString = "regex (empty = wildcard)"
    }
    for err in [appError, bundleError, titleError, subtitleError, bodyError] {
      err.textColor = .systemRed
      err.font = .systemFont(ofSize: 10)
    }
    positionPopUp.addItem(withTitle: "(default)")
    for position in Position.allCases {
      positionPopUp.addItem(withTitle: position.displayName)
    }
    positionPopUp.target = self
    positionPopUp.action = #selector(detailChanged)

    animationPopUp.addItem(withTitle: "(default)")
    for animation in Animation.allCases {
      animationPopUp.addItem(withTitle: animation.displayName)
    }
    animationPopUp.target = self
    animationPopUp.action = #selector(detailChanged)

    func row(_ label: String, _ control: NSView, _ err: NSView? = nil) -> NSStackView {
      let labelView = NSTextField(labelWithString: label)
      labelView.alignment = .right
      labelView.widthAnchor.constraint(equalToConstant: 90).isActive = true
      var subs: [NSView] = [labelView, control]
      if let err { subs.append(err) }
      let rowStack = NSStackView(views: subs)
      rowStack.orientation = .horizontal
      rowStack.spacing = 6
      return rowStack
    }

    let stack = NSStackView(views: [
      row("Name:", nameField),
      row("", enabledButton),
      row("App:", appField, appError),
      row("Bundle ID:", bundleField, bundleError),
      row("Title:", titleField, titleError),
      row("Subtitle:", subtitleField, subtitleError),
      row("Body:", bodyField, bodyError),
      row("Position:", positionPopUp),
      row("Animation:", animationPopUp),
    ])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    return stack
  }

  private func makeTester() -> NSView {
    let header = NSTextField(
      labelWithString: "Test a rule: type sample banner text and see which rule matches.")
    header.font = .boldSystemFont(ofSize: 12)

    for tf in [
      sampleAppField, sampleBundleField, sampleTitleField, sampleSubtitleField, sampleBodyField,
    ] {
      tf.delegate = self
    }

    // Each field gets a caption above it so it is obvious what to type where;
    // fillEqually + a min width keeps them readable across the window.
    let columns = NSStackView(views: [
      labeledField("App", sampleAppField),
      labeledField("Bundle ID", sampleBundleField),
      labeledField("Title", sampleTitleField),
      labeledField("Subtitle", sampleSubtitleField),
      labeledField("Body", sampleBodyField),
    ])
    columns.orientation = .horizontal
    columns.distribution = .fillEqually
    columns.spacing = 8

    let stack = NSStackView(views: [header, columns, testResultLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    return stack
  }

  /// A captioned sample-text input: a small grey label over a regex field.
  private func labeledField(_ caption: String, _ field: NSTextField) -> NSView {
    let label = NSTextField(labelWithString: caption)
    label.font = .systemFont(ofSize: 10)
    label.textColor = .secondaryLabelColor
    field.placeholderString = caption
    field.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
    let column = NSStackView(views: [label, field])
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 2
    return column
  }

  // MARK: Table ops

  private func refreshTable() {
    tableView.reloadData()
    if let index = selectedIndex, rules.indices.contains(index) {
      tableView.selectRowIndexes(
        IndexSet(integer: index), byExtendingSelection: false)
    }
  }

  @objc private func tableSelectionChanged(_ sender: NSTableView) {
    selectedIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
    loadDetailForSelection()
    updateTestResult()
  }

  @objc private func addRule() {
    rules.append(Rule(name: "New Rule"))
    selectedIndex = rules.count - 1
    save()
    refreshTable()
    loadDetailForSelection()
  }

  @objc private func removeRule() {
    guard let index = selectedIndex, rules.indices.contains(index) else { return }
    rules.remove(at: index)
    selectedIndex = rules.isEmpty ? nil : min(index, rules.count - 1)
    save()
    refreshTable()
    loadDetailForSelection()
  }

  // MARK: Detail load/save

  private func loadDetailForSelection() {
    let rule = selectedIndex.flatMap { rules.indices.contains($0) ? rules[$0] : nil }
    let enabled = rule != nil
    for control in [
      nameField, enabledButton, appField, bundleField, titleField,
      subtitleField, bodyField, positionPopUp, animationPopUp,
    ] as [NSControl] {
      control.isEnabled = enabled
    }
    removeButton.isEnabled = enabled
    guard let rule else {
      nameField.stringValue = ""
      enabledButton.state = .off
      for tf in [appField, bundleField, titleField, subtitleField, bodyField] {
        tf.stringValue = ""
      }
      positionPopUp.selectItem(at: 0)
      animationPopUp.selectItem(at: 0)
      clearValidation()
      return
    }
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
    validateAll()
  }

  @objc private func detailChanged() {
    guard let index = selectedIndex, rules.indices.contains(index) else { return }
    var rule = rules[index]
    rule.name = nameField.stringValue
    rule.enabled = enabledButton.state == .on
    rule.appPattern = nilIfEmpty(appField.stringValue)
    rule.bundleIDPattern = nilIfEmpty(bundleField.stringValue)
    rule.titlePattern = nilIfEmpty(titleField.stringValue)
    rule.subtitlePattern = nilIfEmpty(subtitleField.stringValue)
    rule.bodyPattern = nilIfEmpty(bodyField.stringValue)
    let positionIndex = positionPopUp.indexOfSelectedItem
    rule.position = positionIndex == 0 ? nil : Position.allCases[positionIndex - 1]
    let animationIndex = animationPopUp.indexOfSelectedItem
    rule.animation = animationIndex == 0 ? nil : Animation.allCases[animationIndex - 1]
    rules[index] = rule
    save()
    validateAll()
    updateTestResult()
    tableView.reloadData(
      forRowIndexes: IndexSet(integer: index),
      columnIndexes: IndexSet(integersIn: 0..<tableView.tableColumns.count))
  }

  private func nilIfEmpty(_ value: String) -> String? { value.isEmpty ? nil : value }
  private func save() { ruleStore.save(rules) }

  // MARK: Regex validation

  private func validateAll() {
    validate(appField, into: appError)
    validate(bundleField, into: bundleError)
    validate(titleField, into: titleError)
    validate(subtitleField, into: subtitleError)
    validate(bodyField, into: bodyError)
  }

  private func validate(_ field: NSTextField, into err: NSTextField) {
    field.wantsLayer = true
    let pattern = field.stringValue
    if pattern.isEmpty {
      field.layer?.borderWidth = 0
      err.stringValue = ""
      return
    }
    do {
      // Compile with the same option set the runtime matcher applies so
      // a pattern that would behave differently at runtime than under a
      // bare `Regex(pattern)` is caught by the editor's validator.
      _ = try RuleMatcher.compileForMatching(pattern)
      field.layer?.borderWidth = 0
      err.stringValue = ""
    } catch {
      field.layer?.borderColor = NSColor.systemRed.cgColor
      field.layer?.borderWidth = 1
      err.stringValue = "Invalid regex"
    }
  }

  private func clearValidation() {
    for (field, label) in [
      (appField, appError), (bundleField, bundleError),
      (titleField, titleError), (subtitleField, subtitleError),
      (bodyField, bodyError),
    ] {
      field.layer?.borderWidth = 0
      label.stringValue = ""
    }
  }

  // MARK: Sample tester

  @objc private func updateTestResult() {
    let banner = BannerText(
      appName: sampleAppField.stringValue,
      bundleID: nilIfEmpty(sampleBundleField.stringValue),
      title: sampleTitleField.stringValue,
      subtitle: sampleSubtitleField.stringValue,
      body: sampleBodyField.stringValue
    )
    if let match = matcher.match(rules: rules, banner: banner) {
      testResultLabel.stringValue = "Match: \(match.rule.name)"
      testResultLabel.textColor = .systemGreen
    } else {
      testResultLabel.stringValue = "No rule matches."
      testResultLabel.textColor = .secondaryLabelColor
    }
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
    rules.insert(moved, at: min(dst, rules.count))
    selectedIndex = dst
    save()
    refreshTable()
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
      let btn = NSButton(
        checkboxWithTitle: "", target: self, action: #selector(rowEnabledToggled(_:)))
      btn.state = rule.enabled ? .on : .off
      btn.tag = row
      return btn
    case "name": return NSTextField(labelWithString: rule.name)
    case "app": return NSTextField(labelWithString: rule.appPattern ?? "(any)")

    case "rule":
      let pos = rule.position?.displayName ?? "default"
      let anim = rule.animation?.displayName ?? "default"
      return NSTextField(labelWithString: "\(pos) / \(anim)")

    default: return nil
    }
  }

  @objc private func rowEnabledToggled(_ sender: NSButton) {
    let row = sender.tag
    guard rules.indices.contains(row) else { return }
    rules[row].enabled = sender.state == .on
    save()
    if selectedIndex == row { loadDetailForSelection() }
  }
}

// MARK: NSTextFieldDelegate

extension RuleEditorWindowController: NSTextFieldDelegate {
  /// Live updates as the user types: re-run the sample tester for the
  /// tester fields, or validate the regex for a detail field.
  ///
  /// Committing the edit to the rule is deferred to `controlTextDidEndEditing`.
  func controlTextDidChange(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    // Sample-tester fields update on every keystroke.
    if [sampleAppField, sampleTitleField, sampleSubtitleField, sampleBodyField].contains(field) {
      updateTestResult()
      return
    }
    // Detail regex fields: live-validate; commit happens on focus-end.
    switch field {
    case appField: validate(appField, into: appError)
    case bundleField: validate(bundleField, into: bundleError)
    case titleField: validate(titleField, into: titleError)
    case subtitleField: validate(subtitleField, into: subtitleError)
    case bodyField: validate(bodyField, into: bodyError)
    default: break
    }
  }

  /// Commit edits to the selected rule when a detail field loses focus.
  func controlTextDidEndEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    if [nameField, appField, bundleField, titleField, subtitleField, bodyField].contains(field) {
      detailChanged()
    }
  }
}
