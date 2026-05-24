import AppKit
import BannerShiftCore
import Foundation
import OSLog

/// Application entry point and lifecycle owner.
///
/// Wires up the full dependency graph in `applicationDidFinishLaunching`
/// in a strict order (logger → permission → rules → mover → process
/// watcher → menu bar) and fails fast by terminating if the log file
/// can't be opened or Accessibility permission is denied. The dependency
/// properties are late-initialized there and stay nil if startup aborts,
/// which is why teardown uses optional chaining throughout.
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let preferences = Preferences()
  private let osLog = Logger(subsystem: Constants.bundleIdentifier, category: "app")
  private let animator = Animator()

  // Late-init dependencies. Nil until `applicationDidFinishLaunching`
  // wires them up; nil also after a fail-fast termination during that
  // method, which is why `applicationWillTerminate` uses optional
  // chaining throughout.
  private var logger: FileLogger?
  private var ruleStore: RuleStore?
  private var matcher: RuleMatcher?
  private var ruleEditor: RuleEditorWindowController?
  private var mover: BannerMover?
  private var debouncer: Debouncer?
  private var axObserver: AXObserverController?
  private var watcher: NotificationUIWatcher?
  private var menuBar: MenuBarController?

  /// Build the dependency graph and start observing notifications.
  ///
  /// Runs the ordered bring-up described on the type. Terminates the
  /// process — rather than continuing in a degraded state — if the log
  /// file can't be opened or Accessibility permission isn't granted.
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Each step constructs a dependency as a local non-optional, then
    // assigns to self. Downstream steps reference the locals so the
    // chain is checked by the compiler rather than relying on
    // self-properties being non-nil.

    // 1. File logger first so subsequent errors can be recorded.
    let logsDir = FileManager.default
      .urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs")
    let logURL = logsDir.appendingPathComponent("BannerShift.log")
    let logger: FileLogger
    do {
      logger = try FileLogger(
        url: logURL,
        isDebugEnabled: { [preferences] in preferences.debugLoggingEnabled })
    } catch {
      osLog.error("Cannot open log file: \(error.localizedDescription, privacy: .public)")
      NSApp.terminate(nil)
      return
    }
    self.logger = logger
    logger.info("launched")

    // 2. Accessibility permission. Mandatory.
    guard AccessibilityPermission.isTrustedOrPrompt() else {
      logger.error("accessibility permission not granted — terminating")
      osLog.error("accessibility permission not granted — terminating")
      NSApp.terminate(nil)
      return
    }

    // 3. Rule store + editor.
    let ruleStore = RuleStore(
      defaults: .standard,
      logger: { [weak self] msg in self?.logger?.info(msg) }
    )
    self.ruleStore = ruleStore
    let ruleEditor = RuleEditorWindowController(ruleStore: ruleStore)
    self.ruleEditor = ruleEditor

    // 4. Banner mover machinery. The matcher receives a diagnostic sink
    //    so a malformed regex is surfaced to the log rather than silently
    //    disabling the rule with no user-visible trace.
    let matcher = RuleMatcher(
      diagnosticLogger: { [weak self] msg in self?.logger?.error(msg) }
    )
    self.matcher = matcher
    let mover = BannerMover(
      logger: logger,
      preferences: preferences,
      ruleStore: ruleStore,
      matcher: matcher,
      animator: animator
    )
    self.mover = mover
    self.debouncer = Debouncer(interval: Constants.eventDebounceInterval, queue: .main)

    // 5. Workspace observers; start the AX observer when the
    //    notification UI process is up.
    let watcher = NotificationUIWatcher(
      logger: logger,
      onUp: { [weak self] pid in self?.bringUpObserver(pid: pid) },
      onDown: { [weak self] in self?.tearDownObserver() }
    )
    self.watcher = watcher
    watcher.start()

    // 6. Menu bar.
    installMenuBar()
  }

  private func installMenuBar() {
    let menuBar = MenuBarController(
      preferences: preferences,
      onPositionChanged: { [weak self] _ in self?.kickPass() },
      onShowRules: { [weak self] in self?.ruleEditor?.show() },
      onHide: {
        // nothing extra to do
      },
      onQuit: { NSApp.terminate(nil) }
    )
    self.menuBar = menuBar
    if !preferences.iconHidden {
      menuBar.show()
    }
  }

  /// Reveal the menu-bar icon when the user re-activates the app.
  ///
  /// Relaunching or front-launching BannerShift is the documented way
  /// back from "Hide Menu Bar Icon"; this clears `iconHidden` and re-shows
  /// the icon.
  func applicationDidBecomeActive(_ notification: Notification) {
    // Hidden-icon recovery: relaunch (or front-launch) reveals the icon.
    if preferences.iconHidden {
      preferences.iconHidden = false
      menuBar?.show()
    }
  }

  /// Tear down the process watcher and AX observer and flush the log on quit.
  func applicationWillTerminate(_ notification: Notification) {
    watcher?.stop()
    axObserver?.stop()
    logger?.close()
  }

  // MARK: Observer plumbing

  private func bringUpObserver(pid: pid_t) {
    // bringUpObserver is invoked by the workspace watcher, which is
    // only constructed after `logger` is assigned, so a nil logger
    // here means setup failed earlier and the app is terminating —
    // bail rather than start the observer.
    guard let logger else { return }
    // Stop any prior observer before replacing it. On a fast crash-restart of
    // notificationcenterui (or any path where this fires twice without an
    // intervening tearDownObserver), the previous observer's CFRunLoopSource
    // would otherwise remain attached and continue delivering callbacks.
    axObserver?.stop()
    axObserver = nil
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
    mover?.reset()
    debouncer?.cancel()
  }

  private func kickPass() {
    debouncer?.schedule { [weak self] in self?.runPass() }
  }

  /// Run one reposition pass: refresh the window list and move-or-restore.
  private func runPass() {
    axObserver?.refreshWindows()
    let windows = axObserver?.notificationUIWindows() ?? []
    mover?.process(notificationUIWindows: windows)
  }
}
