import ApplicationServices
import BannerShiftCore
import CoreGraphics
import Foundation

final class Animator {
  /// Default delay before the animation starts, in seconds. Tuned to wait
  /// out the OS's own banner-entry animation (§22).
  static let startDelay: TimeInterval = 0.150

  private var workItems: [UInt64: [DispatchWorkItem]] = [:]

  /// Schedule `frames` on the main queue against `window`. Cancels any
  /// previously scheduled animation for `windowID`.
  func animate(
    windowID: UInt64,
    window: AXUIElement,
    frames: [AnimationFrames.Frame],
    delay: TimeInterval = Animator.startDelay
  ) {
    cancel(windowID: windowID)
    var items: [DispatchWorkItem] = []
    let start = DispatchTime.now() + delay
    for frame in frames {
      let item = DispatchWorkItem {
        Animator.set(point: frame.point, on: window)
      }
      DispatchQueue.main.asyncAfter(deadline: start + frame.timeOffset, execute: item)
      items.append(item)
    }
    let totalDuration = (frames.last?.timeOffset ?? 0) + 0.010
    let cleanup = DispatchWorkItem { [weak self] in
      self?.workItems.removeValue(forKey: windowID)
    }
    DispatchQueue.main.asyncAfter(deadline: start + totalDuration, execute: cleanup)
    items.append(cleanup)
    workItems[windowID] = items
  }

  func cancel(windowID: UInt64) {
    if let items = workItems[windowID] {
      for item in items { item.cancel() }
    }
    workItems.removeValue(forKey: windowID)
  }

  func cancelAll() {
    for items in workItems.values {
      for item in items { item.cancel() }
    }
    workItems.removeAll()
  }

  static func set(point: CGPoint, on window: AXUIElement) {
    var p = point
    guard let v = AXValueCreate(.cgPoint, &p) else { return }
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
  }
}
