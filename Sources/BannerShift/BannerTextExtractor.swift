import ApplicationServices
import BannerShiftCore
import CoreGraphics
import Foundation

enum BannerTextExtractor {
  /// Collect text from `banner`'s subtree. Returns ordered strings sorted
  /// top-to-bottom by AX position so the result is deterministic regardless
  /// of AX-tree traversal order.
  ///
  /// The mapping from ordered strings to `BannerText` fields is a best-effort
  /// positional heuristic. Standard macOS banners expose four text elements
  /// (appName, title, subtitle, body), but sparse banners may have fewer:
  /// some apps emit only app+title+body (no subtitle), and system alerts
  /// can be even shorter. To avoid silently misclassifying body text into
  /// the `subtitle` slot for 3-element banners, we fall back to count-aware
  /// assignments below.
  ///
  /// This heuristic is known to be imperfect and will be tuned against real
  /// AX trees during the Task 26 manual smoke test pass.
  static func extract(from banner: AXUIElement) -> BannerText {
    var pairs: [(y: CGFloat, text: String)] = []
    collect(from: banner, into: &pairs)
    let ordered = pairs.sorted(by: { $0.y < $1.y }).map(\.text)
    switch ordered.count {
    case 0:
      return BannerText(appName: "", bundleID: nil, title: "", subtitle: "", body: "")
    case 1:
      return BannerText(appName: ordered[0], bundleID: nil, title: "", subtitle: "", body: "")
    case 2:
      return BannerText(
        appName: ordered[0], bundleID: nil, title: ordered[1], subtitle: "", body: "")
    case 3:
      return BannerText(
        appName: ordered[0], bundleID: nil, title: ordered[1], subtitle: "", body: ordered[2])
    default:
      return BannerText(
        appName: ordered[0], bundleID: nil,
        title: ordered[1], subtitle: ordered[2], body: ordered[3])
    }
  }

  private static func collect(
    from el: AXUIElement,
    into out: inout [(y: CGFloat, text: String)]
  ) {
    // One string per element: prefer AXValue, then AXTitle, then AXDescription.
    let text: String? =
      AXBannerFinder.stringAttribute(el, kAXValueAttribute as CFString)
      ?? AXBannerFinder.stringAttribute(el, kAXTitleAttribute as CFString)
      ?? AXBannerFinder.stringAttribute(el, kAXDescriptionAttribute as CFString)
    if let t = text, !t.isEmpty {
      let y = AXBannerFinder.pointAttribute(el, kAXPositionAttribute as CFString)?.y ?? .infinity
      out.append((y, t))
    }
    for child in AXBannerFinder.arrayAttribute(el, kAXChildrenAttribute as CFString) {
      collect(from: child, into: &out)
    }
  }
}
