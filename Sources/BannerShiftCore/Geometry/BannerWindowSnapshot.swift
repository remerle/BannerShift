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
/// changes. `position` is captured at first sight from the global default
/// so a user changing the default mid-banner does not push the moved
/// banner around. Rule resolution (animation, rule name, pinning) runs
/// *after* the synchronous move dispatches, off the AX-callback critical
/// path: `animation` and `ruleName` stay nil until that async resolve
/// completes. A later pass that finds them already set knows the resolve
/// has run and skips re-resolving. Notification *content* is deliberately
/// not stored here — only the placement it resolved to.
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

  /// Grid cell this banner is moved to.
  ///
  /// Captured from the global default at first sight; no per-rule override,
  /// so the move dispatches synchronously without waiting for rule
  /// resolution.
  public let position: Position

  /// Animation style resolved from the matched rule.
  ///
  /// Set when the post-move async resolve completes. Nil while resolution
  /// is in flight or before it has been scheduled. A non-nil value of
  /// `.none` means resolution ran and no animation was requested.
  public var animation: Animation?

  /// Human-readable name of the matched rule, for diagnostic logging.
  ///
  /// Set alongside `animation` when the async resolve completes. Nil
  /// mirrors `animation == nil`. Falls back to a default marker when no
  /// rule matched.
  public var ruleName: String?

  /// Capture the geometry and position used for the move.
  ///
  /// `animation` and `ruleName` are written later by the async resolve;
  /// callers constructing a first-sight snapshot may leave them at their
  /// nil defaults.
  public init(
    originalOrigin: CGPoint,
    windowFrame: CGRect,
    bannerFrame: CGRect,
    position: Position,
    animation: Animation? = nil,
    ruleName: String? = nil
  ) {
    self.originalOrigin = originalOrigin
    self.windowFrame = windowFrame
    self.bannerFrame = bannerFrame
    self.position = position
    self.animation = animation
    self.ruleName = ruleName
  }
}
