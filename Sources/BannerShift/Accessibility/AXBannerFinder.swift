import ApplicationServices
import BannerShiftCore
import CoreGraphics

/// Reads Accessibility attributes off `AXUIElement`s and locates the
/// banner element inside a notification window.
///
/// Every accessor treats AX data as untrusted: a missing attribute or a
/// type mismatch yields `nil` (or an empty array) rather than trapping,
/// so a malformed tree from the notification UI process degrades to "no
/// banner found" instead of crashing the agent.
enum AXBannerFinder {
  /// Depth-first search for the first descendant of `window` whose
  /// AXSubrole is in `Constants.bannerSubroles`.
  ///
  /// Capped at `Constants.maxAXRecursionDepth` to bound the main-thread
  /// stack against a pathological AX tree from the OS process.
  static func find(in window: AXUIElement) -> AXUIElement? {
    find(in: window, depth: 0)
  }

  private static func find(in window: AXUIElement, depth: Int) -> AXUIElement? {
    if let subrole = stringAttribute(window, kAXSubroleAttribute as CFString),
      Constants.bannerSubroles.contains(subrole)
    {
      return window
    }
    guard depth < Constants.maxAXRecursionDepth else { return nil }
    let children = arrayAttribute(window, kAXChildrenAttribute as CFString)
    for child in children {
      if let hit = find(in: child, depth: depth + 1) { return hit }
    }
    return nil
  }

  /// Combines the element's AX position and size into a frame, or `nil`
  /// if either attribute is missing.
  static func frame(of element: AXUIElement) -> CGRect? {
    guard let pos = pointAttribute(element, kAXPositionAttribute as CFString),
      let size = sizeAttribute(element, kAXSizeAttribute as CFString)
    else { return nil }
    return CGRect(origin: pos, size: size)
  }

  // MARK: AX attribute helpers

  /// Copies a string-valued AX attribute, or `nil` if absent or not a string.
  static func stringAttribute(_ el: AXUIElement, _ attr: CFString) -> String? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success else { return nil }
    return raw as? String
  }

  /// Copies an AX attribute as an array of elements, or `[]` if absent or
  /// not an element array.
  ///
  /// "Empty" and "missing" are intentionally indistinguishable to callers.
  static func arrayAttribute(_ el: AXUIElement, _ attr: CFString) -> [AXUIElement] {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success,
      let arr = raw as? [AXUIElement]
    else { return [] }
    return arr
  }

  /// Extracts a `CGPoint`-valued AX attribute (e.g. `kAXPositionAttribute`),
  /// unwrapping the `AXValue` box; `nil` if absent or not a point.
  static func pointAttribute(_ el: AXUIElement, _ attr: CFString) -> CGPoint? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success,
      let raw,
      CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    // Reason: `as? AXValue` always succeeds for CF types (compiler
    // confirms this), so CFGetTypeID is the only valid runtime check.
    // The guard above verified the type ID, so the force cast is
    // provably safe. This is the canonical AXValue extraction pattern.
    // swift-format-ignore: NeverForceUnwrap
    // swiftlint:disable:next force_cast
    let val = raw as! AXValue
    var point = CGPoint.zero
    guard AXValueGetType(val) == .cgPoint,
      AXValueGetValue(val, .cgPoint, &point)
    else { return nil }
    return point
  }

  /// Extracts a `CGSize`-valued AX attribute (e.g. `kAXSizeAttribute`),
  /// unwrapping the `AXValue` box; `nil` if absent or not a size.
  static func sizeAttribute(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success,
      let raw,
      CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    // Reason: see `pointAttribute` above. CFGetTypeID is the only
    // runtime check that AXValue dispatch supports.
    // swift-format-ignore: NeverForceUnwrap
    // swiftlint:disable:next force_cast
    let val = raw as! AXValue
    var size = CGSize.zero
    guard AXValueGetType(val) == .cgSize,
      AXValueGetValue(val, .cgSize, &size)
    else { return nil }
    return size
  }
}
