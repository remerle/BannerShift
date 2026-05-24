import AppKit
import BannerShiftCore

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

  func start() {
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

  func stop() {
    let nc = NSWorkspace.shared.notificationCenter
    for observer in observers {
      nc.removeObserver(observer)
    }
    observers.removeAll()
  }
}
