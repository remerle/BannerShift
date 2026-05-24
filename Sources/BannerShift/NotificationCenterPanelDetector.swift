import ApplicationServices
import BannerShiftCore

/// Decides whether a notification UI window is the expanded Notification
/// Center panel rather than a transient banner.
///
/// When the user opens Notification Center from the menu bar,
/// `notificationcenterui` emits an AX window with the same role and
/// subroles as a banner. Moving that window onto the user's chosen grid
/// cell would relocate the entire panel and produce a confusing UI;
/// `BannerMover.processWindow` therefore restores the original origin
/// for any window where `isPanel` returns true.
///
/// The detection is structural: the open panel contains an AX element
/// whose `kAXIdentifierAttribute` equals
/// `Constants.notificationCenterPanelIdentifier` (the `widget-editor`
/// magic string). A transient banner never includes that subtree. The
/// identifier is undocumented and OS-fragile — if a future macOS
/// release renames or removes `widget-editor`, this detector returns
/// false for an open panel and the mover will mis-route panel-open
/// events as banner events. The fix in that case is to update the
/// constant in `Constants.swift`.
enum NotificationCenterPanelDetector {
  /// Recursively scans `window` for an AX element whose identifier
  /// matches `Constants.notificationCenterPanelIdentifier`.
  ///
  /// - Parameter window: An AX window element returned by
  ///   `AXObserverController.notificationUIWindows()`.
  /// - Returns: True if the subtree contains the panel marker;
  ///   false for transient banners.
  ///
  /// Called on every reposition pass on the main thread. The AX tree
  /// for a banner is small (typically 2-4 levels) so the recursion is
  /// cheap; if a future OS restructures the notification UI into a
  /// deep tree, this site is a candidate for a depth cap (see also
  /// the same pattern in `AXBannerFinder.find` and
  /// `BannerTextExtractor.collect`).
  static func isPanel(_ window: AXUIElement) -> Bool {
    isPanel(window, depth: 0)
  }

  private static func isPanel(_ window: AXUIElement, depth: Int) -> Bool {
    if let id = AXBannerFinder.stringAttribute(window, kAXIdentifierAttribute as CFString),
      id == Constants.notificationCenterPanelIdentifier
    {
      return true
    }
    guard depth < Constants.maxAXRecursionDepth else { return false }
    for child in AXBannerFinder.arrayAttribute(window, kAXChildrenAttribute as CFString)
    where isPanel(child, depth: depth + 1) {
      return true
    }
    return false
  }
}
