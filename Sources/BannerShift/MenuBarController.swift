import AppKit
import BannerShiftCore

final class MenuBarController: NSObject, NSMenuDelegate {
  private var item: NSStatusItem?
  private let preferences: Preferences
  private let about = AboutWindowController()
  private let onPositionChanged: (Position) -> Void
  private let onShowRules: () -> Void
  private let onQuit: () -> Void
  private let onHide: () -> Void

  init(
    preferences: Preferences,
    onPositionChanged: @escaping (Position) -> Void,
    onShowRules: @escaping () -> Void,
    onHide: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    self.preferences = preferences
    self.onPositionChanged = onPositionChanged
    self.onShowRules = onShowRules
    self.onHide = onHide
    self.onQuit = onQuit
  }

  func show() {
    guard item == nil else { return }
    let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = i.button {
      let img = NSImage(
        systemSymbolName: "bell.badge.fill",
        accessibilityDescription: "BannerShift")
      img?.isTemplate = true
      button.image = img
    }
    let menu = NSMenu()
    menu.delegate = self
    i.menu = menu
    item = i
    rebuildMenu()
  }

  func hide() {
    guard let i = item else { return }
    NSStatusBar.system.removeStatusItem(i)
    item = nil
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuildMenu()
  }

  private func rebuildMenu() {
    guard let menu = item?.menu else { return }
    menu.removeAllItems()

    // Rules… is the most action-oriented item, so it sits at the top
    // above the read-only default-position picker.
    let rulesItem = NSMenuItem(
      title: "Rules\u{2026}",
      action: #selector(showRules(_:)),
      keyEquivalent: "")
    rulesItem.target = self
    menu.addItem(rulesItem)
    menu.addItem(.separator())

    // Default-position picker (used when no rule overrides it).
    let header = NSMenuItem(title: "Default Position", action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    for p in Position.allCases {
      let mi = NSMenuItem(
        title: p.displayName,
        action: #selector(selectPosition(_:)),
        keyEquivalent: "")
      mi.target = self
      mi.representedObject = p
      mi.state = (p == preferences.position) ? .on : .off
      menu.addItem(mi)
    }
    menu.addItem(.separator())

    let test = NSMenuItem(
      title: "Send a Test Notification",
      action: #selector(sendTest(_:)), keyEquivalent: "")
    test.target = self
    menu.addItem(test)
    menu.addItem(.separator())

    // Single IPC to SMAppService.mainApp.status; derive both title and state from it.
    let loginState = LaunchAtLoginToggle.current
    let launch = NSMenuItem(
      title: loginState == .requiresApproval
        ? "Launch at Login (Requires Approval)"
        : "Launch at Login",
      action: #selector(toggleLaunch(_:)), keyEquivalent: "")
    launch.target = self
    launch.state = loginState == .enabled ? .on : .off
    menu.addItem(launch)
    menu.addItem(.separator())

    let hide = NSMenuItem(
      title: "Hide Menu Bar Icon…",
      action: #selector(hideIcon(_:)), keyEquivalent: "")
    hide.target = self
    menu.addItem(hide)
    menu.addItem(.separator())

    let aboutItem = NSMenuItem(
      title: "About BannerShift",
      action: #selector(showAbout(_:)), keyEquivalent: "")
    aboutItem.target = self
    menu.addItem(aboutItem)

    let quit = NSMenuItem(
      title: "Quit BannerShift",
      action: #selector(quit(_:)), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  // MARK: Actions

  @objc private func selectPosition(_ sender: NSMenuItem) {
    guard let p = sender.representedObject as? Position else { return }
    preferences.position = p
    onPositionChanged(p)
  }

  @objc private func sendTest(_ sender: NSMenuItem) {
    TestNotification.send(positionName: preferences.position.displayName)
  }

  @objc private func toggleLaunch(_ sender: NSMenuItem) {
    let newState = LaunchAtLoginToggle.toggle()
    if newState == .requiresApproval {
      let alert = NSAlert()
      alert.messageText = "BannerShift needs approval"
      alert.informativeText = "Approve BannerShift in System Settings → General → Login Items."
      alert.addButton(withTitle: "Open Settings")
      alert.addButton(withTitle: "Cancel")
      if alert.runModal() == .alertFirstButtonReturn {
        LaunchAtLoginToggle.openSettings()
      }
    }
  }

  @objc private func hideIcon(_ sender: NSMenuItem) {
    let alert = NSAlert()
    alert.messageText = "Hide the menu bar icon?"
    alert.informativeText =
      "BannerShift will keep running. Re-launch BannerShift to bring the icon back."
    alert.addButton(withTitle: "Hide")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      preferences.iconHidden = true
      hide()
      onHide()
    }
  }

  @objc private func showAbout(_ sender: NSMenuItem) {
    about.show()
  }

  @objc private func showRules(_ sender: NSMenuItem) {
    onShowRules()
  }

  @objc private func quit(_ sender: NSMenuItem) {
    onQuit()
  }
}
