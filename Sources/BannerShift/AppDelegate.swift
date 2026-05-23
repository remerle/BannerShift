import AppKit
import BannerShiftCore
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let preferences = Preferences()
  private var logger: FileLogger!
  private var osLog = Logger(subsystem: Constants.bundleIdentifier, category: "app")
  private var ruleStore: RuleStore!
  private var matcher: RuleMatcher!
  private let animator = Animator()
  private var ruleEditor: RuleEditorWindowController!
  private var mover: BannerMover!
  private var debouncer: Debouncer!
  private var axObserver: AXObserverController?
  private var watcher: NotificationUIWatcher!
  private var menuBar: MenuBarController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    // 1. File logger first so subsequent errors can be recorded.
    let logsDir = FileManager.default
      .urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs")
    let logURL = logsDir.appendingPathComponent("BannerShift.log")
    do {
      logger = try FileLogger(
        url: logURL,
        isDebugEnabled: { [preferences] in preferences.debugLoggingEnabled })
    } catch {
      osLog.error("Cannot open log file: \(error.localizedDescription, privacy: .public)")
      NSApp.terminate(nil)
      return
    }
    logger.info("launched")

    // 2. Accessibility permission. Mandatory.
    guard AccessibilityPermission.isTrustedOrPrompt() else {
      logger.error("accessibility permission not granted — terminating")
      osLog.error("accessibility permission not granted — terminating")
      NSApp.terminate(nil)
      return
    }

    // 3. Rule store + editor.
    ruleStore = RuleStore(
      defaults: .standard,
      logger: { [weak self] msg in self?.logger.info(msg) }
    )
    ruleEditor = RuleEditorWindowController(ruleStore: ruleStore)

    // 4. Banner mover machinery. The matcher receives a diagnostic sink
    //    so a malformed regex is surfaced to the log rather than silently
    //    disabling the rule with no user-visible trace.
    matcher = RuleMatcher(
      diagnosticLogger: { [weak self] msg in self?.logger.error(msg) }
    )
    mover = BannerMover(
      logger: logger,
      preferences: preferences,
      ruleStore: ruleStore,
      matcher: matcher,
      animator: animator
    )
    debouncer = Debouncer(interval: Constants.eventDebounceInterval, queue: .main)

    // 5. Workspace observers; start the AX observer when the
    //    notification UI process is up.
    watcher = NotificationUIWatcher(
      logger: logger,
      onUp: { [weak self] pid in self?.bringUpObserver(pid: pid) },
      onDown: { [weak self] in self?.tearDownObserver() }
    )
    watcher.start()

    // 6. Menu bar.
    menuBar = MenuBarController(
      preferences: preferences,
      onPositionChanged: { [weak self] _ in self?.kickPass() },
      onShowRules: { [weak self] in self?.ruleEditor.show() },
      onHide: {
        // nothing extra to do
      },
      onQuit: { NSApp.terminate(nil) }
    )
    if !preferences.iconHidden {
      menuBar.show()
    }
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    // Hidden-icon recovery: relaunch (or front-launch) reveals the icon.
    if preferences.iconHidden {
      preferences.iconHidden = false
      menuBar.show()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    watcher?.stop()
    axObserver?.stop()
    logger?.close()
  }

  // MARK: Observer plumbing

  private func bringUpObserver(pid: pid_t) {
    let observer = AXObserverController(pid: pid, logger: logger)
    axObserver = observer
    guard observer.start(handler: { [weak self] in self?.kickPass() }) else {
      logger.error("AXObserverController: failed to start — terminating")
      osLog.error("AXObserverController: failed to start — terminating")
      NSApp.terminate(nil)
      return
    }
    kickPass()  // initial sweep
  }

  private func tearDownObserver() {
    axObserver?.stop()
    axObserver = nil
    mover.reset()
    debouncer.cancel()
  }

  private func kickPass() {
    debouncer.schedule { [weak self] in
      guard let self else { return }
      self.axObserver?.refreshWindows()
      let windows = self.axObserver?.notificationUIWindows() ?? []
      self.mover.process(notificationUIWindows: windows)
    }
  }
}
