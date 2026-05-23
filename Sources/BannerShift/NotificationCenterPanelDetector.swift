import ApplicationServices
import BannerShiftCore

enum NotificationCenterPanelDetector {
  static func isPanel(_ window: AXUIElement) -> Bool {
    if let id = AXBannerFinder.stringAttribute(window, kAXIdentifierAttribute as CFString),
      id == Constants.notificationCenterPanelIdentifier
    {
      return true
    }
    for child in AXBannerFinder.arrayAttribute(window, kAXChildrenAttribute as CFString)
    where isPanel(child) {
      return true
    }
    return false
  }
}
