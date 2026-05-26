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
///
/// Because the notification UI hands out a unique, short-lived window per
/// banner, a window identity maps to exactly one banner whose text never
/// changes. The snapshot therefore also caches the *resolved* placement
/// (`position`, `animation`, and the diagnostic `ruleName`) computed at first
/// sight, so the expensive AX text extraction and rule match run once per
/// banner instead of once per debounce pass. Notification *content* is
/// deliberately not stored here — only the placement it resolved to.
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

  /// Grid cell this banner resolved to at first sight (a concrete cell, with
  /// the global default already applied when no rule overrode it).
  public let position: Position

  /// Animation style this banner resolved to at first sight.
  public let animation: Animation

  /// Human-readable name of the rule that matched, or a default marker, for
  /// diagnostic logging only.
  public let ruleName: String

  /// Captures the geometry and resolved placement needed for repositioning,
  /// restore, and re-application on later passes.
  public init(
    originalOrigin: CGPoint,
    windowFrame: CGRect,
    bannerFrame: CGRect,
    position: Position,
    animation: Animation,
    ruleName: String
  ) {
    self.originalOrigin = originalOrigin
    self.windowFrame = windowFrame
    self.bannerFrame = bannerFrame
    self.position = position
    self.animation = animation
    self.ruleName = ruleName
  }
}
