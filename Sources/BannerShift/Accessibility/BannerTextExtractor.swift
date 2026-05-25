import ApplicationServices
import BannerShiftCore
import CoreGraphics

/// Reads the visible text of a banner out of its Accessibility subtree
/// and packs it into a `BannerText` for rule matching.
///
/// This is the executable-side counterpart to Core's `RuleMatcher`: it
/// turns the live AX tree into the plain value type the matcher consumes.
/// Treat its output as sensitive — it is the full visible text of the
/// user's notification and must not be logged outside debug mode.
enum BannerTextExtractor {
  /// Build a banner-text snapshot from the AX subtree rooted at `banner`.
  ///
  /// Walks the AX subtree, sorts the discovered text elements
  /// top-to-bottom by AX position so the result is deterministic
  /// regardless of AX-tree traversal order, then assigns them to
  /// `BannerText` fields with a best-effort positional heuristic.
  ///
  /// Standard macOS banners expose four text elements (appName, title,
  /// subtitle, body), but sparse banners may have fewer: some apps
  /// emit only app+title+body (no subtitle), and system alerts can be
  /// even shorter. To avoid silently misclassifying body text into the
  /// `subtitle` slot for 3-element banners, the assignment is
  /// count-aware (see the switch below).
  ///
  /// This heuristic is imperfect and is expected to be revisited as
  /// real-world AX-tree shapes are observed across macOS versions.
  static func extract(from banner: AXUIElement) -> BannerText {
    var pairs: [(y: CGFloat, text: String)] = []
    collect(from: banner, into: &pairs, depth: 0)
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
      // Five or more text elements: macOS has historically capped banners
      // at four (app / title / subtitle / body). If a future OS revision
      // adds a fifth element (e.g. action button label, secondary body),
      // it lands here and is silently dropped — the assignment below
      // takes only ordered[0..<4]. When that happens, extend the switch
      // with a new case for the higher count rather than reshaping the
      // existing branches.
      return BannerText(
        appName: ordered[0], bundleID: nil,
        title: ordered[1], subtitle: ordered[2], body: ordered[3])
    }
  }

  private static func collect(
    from el: AXUIElement,
    into out: inout [(y: CGFloat, text: String)],
    depth: Int
  ) {
    // One string per element: prefer AXValue, then AXTitle, then AXDescription.
    let text: String? =
      AXBannerFinder.stringAttribute(el, kAXValueAttribute as CFString)
      ?? AXBannerFinder.stringAttribute(el, kAXTitleAttribute as CFString)
      ?? AXBannerFinder.stringAttribute(el, kAXDescriptionAttribute as CFString)
    if let text, !text.isEmpty {
      let y = AXBannerFinder.pointAttribute(el, kAXPositionAttribute as CFString)?.y ?? .infinity
      out.append((y, text))
    }
    guard depth < Constants.maxAXRecursionDepth else { return }
    for child in AXBannerFinder.arrayAttribute(el, kAXChildrenAttribute as CFString) {
      collect(from: child, into: &out, depth: depth + 1)
    }
  }
}
