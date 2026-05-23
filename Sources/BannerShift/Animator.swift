import ApplicationServices
import BannerShiftCore
import CoreGraphics
import Foundation

final class Animator {
  /// Default delay before the animation starts, in seconds.
  ///
  /// Tuned to wait out the OS's own banner-entry animation so our
  /// motion begins from a settled banner rather than fighting the
  /// system animation.
  static let startDelay: TimeInterval = 0.150

  private var workItems: [UInt64: [DispatchWorkItem]] = [:]

  /// Schedule `frames` on the main queue against `window`.
  ///
  /// Cancels any previously scheduled animation for `windowID` so a
  /// rapid sequence of repositions never produces overlapping writes
  /// to the same window's AX position attribute.
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
        Self.set(point: frame.point, on: window)
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
    var mutablePoint = point
    guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else { return }
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
  }
}
