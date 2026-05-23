import AppKit
import ApplicationServices
import BannerShiftCore
import CoreGraphics

final class AXObserverController {
  typealias EventHandler = () -> Void

  private let pid: pid_t
  private let appElement: AXUIElement
  private var observer: AXObserver?
  private var runLoopSource: CFRunLoopSource?
  private var registeredWindowKeys: Set<ObserverKey> = []
  private var handler: EventHandler?
  private let logger: FileLogger

  // Spec §4.3 requires observation of window creation, banner element creation,
  // and window destruction. The macOS AX API does not expose a dedicated
  // "children changed" notification; descendant-created (kAXCreatedNotification)
  // covers the children-changed semantics from spec §4.3 by firing whenever any
  // new AXUIElement is created in the observed process, which is how we catch
  // banners that appear inside an already-existing notification UI window.
  // kAXLayoutChangedNotification catches geometry-only updates that don't create
  // new elements.
  private static let notifications: [String] = [
    kAXWindowCreatedNotification,
    kAXCreatedNotification,
    kAXUIElementDestroyedNotification,
    kAXLayoutChangedNotification,
  ]

  init(pid: pid_t, logger: FileLogger) {
    self.pid = pid
    self.appElement = AXUIElementCreateApplication(pid)
    self.logger = logger
  }

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
  func refreshWindows() {
    guard observer != nil else { return }
    let children = AXBannerFinder.arrayAttribute(appElement, kAXWindowsAttribute as CFString)
    for window in children {
      let key = makeKey(for: window)
      if !registeredWindowKeys.contains(key) {
        register(element: window)
        registeredWindowKeys.insert(key)
      }
    }
  }

  func notificationUIWindows() -> [AXUIElement] {
    AXBannerFinder.arrayAttribute(appElement, kAXWindowsAttribute as CFString)
  }

  private func register(element: AXUIElement) {
    guard let observer else { return }
    let selfPtr = Unmanaged.passUnretained(self).toOpaque()
    for notif in Self.notifications {
      AXObserverAddNotification(observer, element, notif as CFString, selfPtr)
    }
  }

  private func makeKey(for window: AXUIElement) -> ObserverKey {
    let role = AXBannerFinder.stringAttribute(window, kAXRoleAttribute as CFString) ?? "?"
    let subrole = AXBannerFinder.stringAttribute(window, kAXSubroleAttribute as CFString) ?? "?"
    let size = AXBannerFinder.sizeAttribute(window, kAXSizeAttribute as CFString) ?? .zero
    let id = UInt64(UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque()))
    return ObserverKey(elementID: id, role: role, subrole: subrole, size: size)
  }

  // C callback; trampoline into the Swift handler.
  private static let callback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let me = Unmanaged<AXObserverController>.fromOpaque(refcon).takeUnretainedValue()
    me.handler?()
  }
}
