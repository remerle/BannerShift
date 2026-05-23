import ApplicationServices
import BannerShiftCore
import CoreGraphics

enum AXBannerFinder {
  /// Depth-first search for the first descendant of `window` whose
  /// AXSubrole is in `Constants.bannerSubroles`.
  static func find(in window: AXUIElement) -> AXUIElement? {
    if let subrole = stringAttribute(window, kAXSubroleAttribute as CFString),
      Constants.bannerSubroles.contains(subrole)
    {
      return window
    }
    let children = arrayAttribute(window, kAXChildrenAttribute as CFString)
    for child in children {
      if let hit = find(in: child) { return hit }
    }
    return nil
  }

  static func frame(of element: AXUIElement) -> CGRect? {
    guard let pos = pointAttribute(element, kAXPositionAttribute as CFString),
      let size = sizeAttribute(element, kAXSizeAttribute as CFString)
    else { return nil }
    return CGRect(origin: pos, size: size)
  }

  // MARK: AX attribute helpers

  static func stringAttribute(_ el: AXUIElement, _ attr: CFString) -> String? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success else { return nil }
    return raw as? String
  }

  static func arrayAttribute(_ el: AXUIElement, _ attr: CFString) -> [AXUIElement] {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success,
      let arr = raw as? [AXUIElement]
    else { return [] }
    return arr
  }

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
