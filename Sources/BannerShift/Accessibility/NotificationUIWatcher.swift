import AppKit
import BannerShiftCore

/// Watches for the notification UI process
/// (`com.apple.notificationcenterui`) launching and terminating, so the
/// AX observer can be attached to its pid and torn down when it exits.
///
/// That process can crash and relaunch independently of this app; the
/// watcher is what lets BannerShift re-attach instead of going dead after
/// the first restart. All callbacks are delivered on the main queue.
final class NotificationUIWatcher {
  private let logger: FileLogger
  private let onUp: (pid_t) -> Void
  private let onDown: () -> Void
  private var observers: [NSObjectProtocol] = []

  init(
    logger: FileLogger,
    onUp: @escaping (pid_t) -> Void,
    onDown: @escaping () -> Void
  ) {
    self.logger = logger
    self.onUp = onUp
    self.onDown = onDown
  }

  /// Begin watching, firing `onUp` immediately if the notification UI
  /// process is already running.
  ///
  /// `onUp(pid)` fires on launch (and once now for an already-running
  /// process); `onDown` fires on termination. Idempotent: a second call
  /// while already watching is a logged no-op, so a duplicate `start()`
  /// cannot double-register the workspace observers (which would fire every
  /// callback twice). Call `stop()` before `start()` to re-arm.
  func start() {
    guard observers.isEmpty else {
      logger.info("NotificationUIWatcher.start() called while already watching; ignoring")
      return
    }
    let nc = NSWorkspace.shared.notificationCenter
    observers.append(
      nc.addObserver(
        forName: NSWorkspace.didLaunchApplicationNotification,
        object: nil, queue: .main
      ) { [weak self] note in
        guard let self else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        if app.bundleIdentifier == Constants.notificationUIBundleIdentifier {
          self.logger.info("notification UI launched (pid=\(app.processIdentifier))")
          self.onUp(app.processIdentifier)
        }
      })
    observers.append(
      nc.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification,
        object: nil, queue: .main
      ) { [weak self] note in
        guard let self else { return }
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        if app.bundleIdentifier == Constants.notificationUIBundleIdentifier {
          self.logger.info("notification UI terminated")
          self.onDown()
        }
      })

    if let running = NSWorkspace.shared.runningApplications.first(
      where: { $0.bundleIdentifier == Constants.notificationUIBundleIdentifier }
    ) {
      onUp(running.processIdentifier)
    }
  }

  /// Remove the workspace observers registered by `start()`.
  func stop() {
    let nc = NSWorkspace.shared.notificationCenter
    for observer in observers {
      nc.removeObserver(observer)
    }
    observers.removeAll()
  }
}
