import ApplicationServices
import BannerShiftCore
import CoreGraphics

/// Owns an `AXObserver` for the notification UI process and trampolines
/// AX events back into Swift.
///
/// One instance is created per notification UI process lifetime by
/// `AppDelegate.bringUpObserver(pid:)`; `tearDownObserver()` drops it
/// when the process exits and `bringUpObserver` first stops any prior
/// observer before replacing it.
///
/// All methods are main-thread-only. The `CFRunLoopSource` produced by
/// `AXObserverGetRunLoopSource` is attached to `CFRunLoopGetCurrent()`,
/// which is the main run loop in our usage; touching the controller
/// from another queue would either race the observer state or attach
/// the source to a non-main run loop and miss every event.
final class AXObserverController {
  typealias EventHandler = () -> Void

  private let pid: pid_t
  private let appElement: AXUIElement
  private var observer: AXObserver?
  private var runLoopSource: CFRunLoopSource?
  private var registeredWindowKeys: Set<AXWindowKey> = []
  private var handler: EventHandler?
  private let logger: FileLogger

  // We must observe window creation, banner element creation, and window
  // destruction to react to every banner-lifecycle event. The macOS AX API
  // does not expose a dedicated "children changed" notification;
  // kAXCreatedNotification fills the gap by firing whenever any new
  // AXUIElement is created in the observed process, which is how we catch
  // banners that appear inside an already-existing notification UI window.
  // kAXLayoutChangedNotification catches geometry-only updates that don't
  // create new elements.
  private static let notifications: [String] = [
    kAXWindowCreatedNotification,
    kAXCreatedNotification,
    kAXUIElementDestroyedNotification,
    kAXLayoutChangedNotification,
  ]

  /// - Parameters:
  ///   - pid: Process ID of the notification UI process to observe.
  ///   - logger: Sink for non-fatal AX errors (observer create failure,
  ///     per-element registration failure). Fatal startup failure is
  ///     surfaced through `start(handler:)` returning false; callers
  ///     are expected to terminate in that case.
  init(pid: pid_t, logger: FileLogger) {
    self.pid = pid
    self.appElement = AXUIElementCreateApplication(pid)
    self.logger = logger
  }

  /// Create the `AXObserver`, attach its run-loop source to the main
  /// run loop, and register for AX notifications on the app element
  /// plus every existing window.
  ///
  /// - Parameter handler: Closure invoked on every AX callback. Stored
  ///   as a property so the C trampoline (`Self.callback`) can read it
  ///   via the retained-`self` pointer; cleared in `stop()`.
  /// - Returns: True on success. False means the `AXObserver` could
  ///   not be created (logged) and the caller must terminate; the
  ///   `@discardableResult` is paired with that contract.
  @discardableResult
  func start(handler: @escaping EventHandler) -> Bool {
    self.handler = handler
    var rawObserver: AXObserver?
    let result = AXObserverCreate(pid, Self.callback, &rawObserver)
    guard result == .success, let observer = rawObserver else {
      logger.error("AXObserverController: AXObserverCreate failed (\(result.rawValue))")
      return false
    }
    self.observer = observer
    let source = AXObserverGetRunLoopSource(observer)
    self.runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    register(element: appElement)
    refreshWindows()
    return true
  }

  /// Detach the run-loop source, clear the event handler, and release
  /// the `AXObserver` and per-window key set.
  ///
  /// Safe to call multiple times. Called from `tearDownObserver()`,
  /// from `bringUpObserver` before a replacement controller is
  /// constructed, and from `applicationWillTerminate`.
  func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
      runLoopSource = nil
    }
    // Clear the handler before dropping the observer so any in-flight callback
    // that has already escaped the run-loop check is a no-op on a stale pointer.
    handler = nil
    observer = nil
    registeredWindowKeys.removeAll()
  }

  /// Called by clients (typically on the debounce pass) to pick up
  /// windows created since startup.
  ///
  /// Prunes keys for windows that no longer appear in
  /// `kAXWindowsAttribute` so the set stays bounded by the current live
  /// window count. Pruning also prevents AX pointer reuse from skipping
  /// a real new window: without the prune, a destroyed window's key can
  /// coincidentally match a new window's key and the new window would
  /// never receive its per-window notifications.
  func refreshWindows() {
    guard observer != nil else { return }
    let children = AXBannerFinder.arrayAttribute(appElement, kAXWindowsAttribute as CFString)
    let liveKeys = Set(children.map { makeKey(for: $0) })
    registeredWindowKeys.formIntersection(liveKeys)
    for window in children {
      let key = makeKey(for: window)
      if !registeredWindowKeys.contains(key) {
        register(element: window)
        registeredWindowKeys.insert(key)
      }
    }
  }

  /// Current top-level windows of the notification UI process.
  ///
  /// Returned in the order `AXUIElementCopyAttributeValue` provides
  /// (typically newest-last). Callers iterate and filter for banners
  /// vs. the open Notification Center panel via
  /// `NotificationCenterPanelDetector.isPanel`.
  func notificationUIWindows() -> [AXUIElement] {
    AXBannerFinder.arrayAttribute(appElement, kAXWindowsAttribute as CFString)
  }

  private func register(element: AXUIElement) {
    guard let observer else { return }
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    for notif in Self.notifications {
      let err = AXObserverAddNotification(observer, element, notif as CFString, selfPtr)
      // Treat success and the benign "already registered" race as expected;
      // log everything else so a fast-dismissing banner that returns
      // `kAXErrorInvalidUIElement` produces a diagnostic trail rather than
      // silently missing its events.
      if err != .success && err != .notificationAlreadyRegistered {
        logger.error(
          "AXObserverController: AXObserverAddNotification failed for \(notif) (\(err.rawValue))"
        )
      }
    }
  }

  private func makeKey(for window: AXUIElement) -> AXWindowKey {
    let role = AXBannerFinder.stringAttribute(window, kAXRoleAttribute as CFString) ?? "?"
    let subrole = AXBannerFinder.stringAttribute(window, kAXSubroleAttribute as CFString) ?? "?"
    let size = AXBannerFinder.sizeAttribute(window, kAXSizeAttribute as CFString) ?? .zero
    // Identify the element by `CFHash`, not its boxed pointer: `kAXWindows`
    // returns a fresh `AXUIElement` box on every query, so the raw pointer
    // differs pass-to-pass for the same window (see `BannerMover.elementID`).
    // Keying on the pointer would empty `registeredWindowKeys` on every refresh
    // and re-register every window each pass. `CFHash` is derived from the
    // underlying element identity (consistent with `CFEqual`) and stays stable
    // across those copies, so the de-dup set actually dedups.
    let id = UInt64(CFHash(window))
    return AXWindowKey(elementID: id, role: role, subrole: subrole, size: size)
  }

  // C callback; trampoline into the Swift handler.
  private static let callback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let me = Unmanaged<AXObserverController>.fromOpaque(refcon).takeUnretainedValue()
    me.handler?()
  }
}
