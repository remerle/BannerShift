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
    let val = raw as! AXValue  // safe: CFTypeID checked above
    var p = CGPoint.zero
    guard AXValueGetType(val) == .cgPoint,
      AXValueGetValue(val, .cgPoint, &p)
    else { return nil }
    return p
  }

  static func sizeAttribute(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success,
      let raw,
      CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    let val = raw as! AXValue  // safe: CFTypeID checked above
    var s = CGSize.zero
    guard AXValueGetType(val) == .cgSize,
      AXValueGetValue(val, .cgSize, &s)
    else { return nil }
    return s
  }
}
