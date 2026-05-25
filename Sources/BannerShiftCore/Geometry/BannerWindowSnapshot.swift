import CoreGraphics

/// First-sighting snapshot of a banner window, captured once per window
/// identity and held by `BannerMover` until the banner disappears.
///
/// Two reposition passes against the same window must produce the same
/// target geometry, so the math reads window/banner sizes from this
/// snapshot rather than re-querying AX (where in-flight animations would
/// otherwise feed back into subsequent passes). The snapshot also
/// remembers `originalOrigin` so the window can be restored to the
/// OS-default position when the banner is dismissed.
public struct BannerWindowSnapshot: Equatable, Sendable {
  /// Window origin as the OS placed it before any reposition.
  ///
  /// Used as the restore target when a window we moved turns out to be the
  /// Notification Center panel and must be put back.
  public let originalOrigin: CGPoint

  /// Window frame at first sight.
  ///
  /// The reposition math reads width and height from here rather than
  /// re-querying AX each tick, so an in-flight animation cannot feed
  /// back into subsequent passes.
  public let windowFrame: CGRect

  /// Banner frame inside the container window at first sight.
  ///
  /// The banner's offset within the window is what makes the reposition
  /// math non-trivial; capturing it once avoids drift.
  public let bannerFrame: CGRect

  /// Captures the geometry needed for both repositioning and restore.
  public init(originalOrigin: CGPoint, windowFrame: CGRect, bannerFrame: CGRect) {
    self.originalOrigin = originalOrigin
    self.windowFrame = windowFrame
    self.bannerFrame = bannerFrame
  }
}
