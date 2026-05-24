import AppKit
import BannerShiftCore
import Foundation

final class RuleEditorWindowController: NSWindowController {
  private let ruleStore: RuleStore
  private let matcher = RuleMatcher()
  private var rules: [Rule] = []
  private var selectedIndex: Int?

  // List pane
  private let tableView = NSTableView()
  private let addButton = NSButton(title: "Add", target: nil, action: nil)
  private let removeButton = NSButton(title: "Remove", target: nil, action: nil)

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

  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.bringToFront()
  }

  // MARK: UI

  private func buildUI() {
    guard let content = window?.contentView else { return }

    configureTable()
    addButton.target = self
    addButton.action = #selector(addRule)
    removeButton.target = self
    removeButton.action = #selector(removeRule)
    let listButtons = NSStackView(views: [addButton, removeButton])
    listButtons.orientation = .horizontal
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
    outer.alignment = .leading
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
    let header = NSTextField(labelWithString: "Test against sample text:")
    header.font = .boldSystemFont(ofSize: 12)
    let fields = [
      sampleAppField, sampleBundleField, sampleTitleField, sampleSubtitleField, sampleBodyField,
    ]
    for tf in fields {
      tf.delegate = self
    }
    sampleAppField.placeholderString = "App"
    sampleBundleField.placeholderString = "Bundle ID"
    sampleTitleField.placeholderString = "Title"
    sampleSubtitleField.placeholderString = "Subtitle"
    sampleBodyField.placeholderString = "Body"
    let inputs = NSStackView(views: fields)
    inputs.orientation = .horizontal
    inputs.distribution = .fillEqually
    inputs.spacing = 6
    let stack = NSStackView(views: [header, inputs, testResultLabel])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    return stack
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

  func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
    let item = NSPasteboardItem()
    item.setString("\(row)", forType: .string)
    return item
  }

  func tableView(
    _ tableView: NSTableView,
    validateDrop info: NSDraggingInfo,
    proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
  ) -> NSDragOperation {
    dropOperation == .above ? .move : []
  }

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

  func controlTextDidEndEditing(_ obj: Notification) {
    guard let field = obj.object as? NSTextField else { return }
    if [nameField, appField, bundleField, titleField, subtitleField, bodyField].contains(field) {
      detailChanged()
    }
  }
}
