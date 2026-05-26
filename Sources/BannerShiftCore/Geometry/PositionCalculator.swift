import CoreGraphics

/// Computes the target *window origin* in AX (top-left origin) coordinates such
/// that the banner inside the window lands on the chosen 3x3 cell of the chosen
/// display.
///
/// AX exposes window position only — not the banner's frame inside the window —
/// so the math has to account for the banner's offset within its container
/// window. The notification UI process places banners inside a full-display
/// container window whose height equals the display's height; that invariant
/// is checked by `invariantHolds` and any caller should bail when it fails.
public struct PositionCalculator {
  /// AX-space frame of the container window holding the banner.
  ///
  /// Read from `BannerWindowSnapshot.windowFrame` so an in-flight
  /// animation cannot feed back into the math.
  public let windowFrame: CGRect

  /// AX-space frame of the banner element inside `windowFrame`.
  ///
  /// Also read from `BannerWindowSnapshot` for the same reason: stability
  /// across repeated passes against the same window.
  public let bannerFrame: CGRect

  /// Snapshot of the display the banner should land on.
  public let screen: ScreenInfo

  /// AppKit→AX y-flip pivot.
  ///
  /// Must be the *primary* display's height, not the chosen display's
  /// height. Same-height monitor setups land on the correct value
  /// either way; heterogeneous-height multi-monitor setups will
  /// mis-place banners on the non-primary display if the chosen
  /// display's height is used here.
  public let primaryHeight: CGFloat

  /// Captures the inputs needed by the position math.
  ///
  /// The calculator is a pure value; one is constructed per banner
  /// per reposition pass.
  public init(
    windowFrame: CGRect,
    bannerFrame: CGRect,
    screen: ScreenInfo,
    primaryHeight: CGFloat
  ) {
    self.windowFrame = windowFrame
    self.bannerFrame = bannerFrame
    self.screen = screen
    self.primaryHeight = primaryHeight
  }

  /// Computes the banner's *resting* frame in window-relative coordinates
  /// from the live (screen-space AX) window and banner frames.
  ///
  /// `bannerFrame` everywhere in this type is window-relative (offset from
  /// the container window's origin, range `0...windowFrame.width` /
  /// `0...windowFrame.height`); `invariantHolds` enforces that. AX, however,
  /// reports both the window and the banner in screen-space, top-left-origin
  /// coordinates, so the live banner frame must be rebased onto the window
  /// before it can feed the position math. This is the single place that
  /// conversion happens.
  ///
  /// Two adjustments are applied:
  /// - **x** anchors to the banner's fixed resting inset from the window's
  ///   right edge (`Constants.bannerRightPadding`), not the live `minX`,
  ///   which is still off-screen mid-slide-in. The result is the window-
  ///   relative left edge the banner settles at.
  /// - **y** is rebased to window-relative by subtracting the window's AX
  ///   origin. On the primary display the container window's AX origin is
  ///   `(0, 0)`, so this is a no-op there; on a display positioned above the
  ///   primary the window's AX origin y is negative, and without this
  ///   subtraction the banner's screen-space y leaks through, making
  ///   `invariantHolds` reject the (valid) layout and the banner never moves.
  ///
  /// - Parameters:
  ///   - windowFrame: Screen-space AX frame of the container window.
  ///   - liveBannerFrame: Screen-space AX frame of the banner element.
  /// - Returns: The banner's resting frame in window-relative coordinates,
  ///   suitable as the `bannerFrame` argument to `init`.
  public static func restingBannerFrame(
    windowFrame: CGRect, liveBannerFrame: CGRect
  ) -> CGRect {
    CGRect(
      x: windowFrame.width - liveBannerFrame.width - Constants.bannerRightPadding,
      y: liveBannerFrame.minY - windowFrame.origin.y,
      width: liveBannerFrame.width,
      height: liveBannerFrame.height
    )
  }

  /// True iff the AX container window is the full height of the
  /// display.
  ///
  /// This is the invariant the rest of the math depends on; callers
  /// must check it before trusting `targetOrigin(for:)`. Violations
  /// are typically caused by a macOS update changing the notification
  /// UI's window layout.
  ///
  /// The comparison uses a sub-pixel tolerance because AX-sourced and
  /// NSScreen-sourced heights flow through different conversions and
  /// can diverge by floating-point noise smaller than a logical pixel.
  /// `1.0` is large enough to absorb that noise and small enough to
  /// still catch every structural violation we have ever seen
  /// (typically a multi-hundred-point delta).
  public var invariantHolds: Bool {
    guard abs(windowFrame.size.height - screen.frame.size.height) < 1.0
    else { return false }
    // Also reject degenerate visible-frame geometry that would produce
    // NaN/Inf or visually wrong positions for middle/bottom rows. A
    // zero-height visible area can occur transiently during display
    // reconfiguration; bail out rather than emit nonsense coordinates.
    guard screen.visibleFrame.size.height > 0,
      screen.visibleFrame.size.width > 0
    else { return false }
    // Sanity-check that the banner sits inside the window. AX data is
    // external OS state; an out-of-bounds banner frame would project
    // the window origin far off-screen (e.g. a banner with minX =
    // -10000 yields a windowOrigin of +10000). The bannerFrame is in
    // window-relative coordinates so the expected range is
    // 0...windowFrame.width / 0...windowFrame.height.
    guard bannerFrame.minX >= 0,
      bannerFrame.minY >= 0,
      bannerFrame.maxX <= windowFrame.width + 1.0,
      bannerFrame.maxY <= windowFrame.height + 1.0
    else { return false }
    return true
  }

  /// Computes the integer-snapped target window origin (AX coordinates,
  /// top-left origin) for the given 3x3 cell.
  ///
  /// - Parameter position: Which of the nine grid cells to anchor on.
  /// - Returns: Window origin rounded to integer points so the banner
  ///   renders crisply at any DPI.
  public func targetOrigin(for position: Position) -> CGPoint {
    let x = horizontalOrigin(for: position.horizontal)
    let y = verticalOrigin(for: position.vertical)
    return CGPoint(x: x.rounded(), y: y.rounded())
  }

  // MARK: - Horizontal

  private func horizontalOrigin(for horizontal: Position.Horizontal) -> CGFloat {
    switch horizontal {
    case .right:
      // OS already places the banner at the right edge; keep window origin as-is.
      return windowFrame.origin.x

    case .left:
      // Want banner left edge at screen.frame.minX. Banner sits at bannerFrame.minX
      // inside the window, so shift the window so that windowOriginX + bannerMinX = screenMinX.
      return screen.frame.minX - bannerFrame.minX

    case .center:
      // Centered banner left in screen space = screen.minX + (screen.width - banner.width)/2.
      let centeredBannerLeft =
        screen.frame.minX + (screen.frame.width - bannerFrame.width) / 2
      return centeredBannerLeft - bannerFrame.minX
    }
  }

  // MARK: - Vertical

  /// Top edge of the visible area expressed in AX (top-left origin) space.
  private var visibleTopAX: CGFloat {
    primaryHeight - screen.visibleFrame.maxY
  }

  /// Bottom edge of the visible area expressed in AX (top-left origin) space.
  private var visibleBottomAX: CGFloat {
    primaryHeight - screen.visibleFrame.minY
  }

  private func verticalOrigin(for vertical: Position.Vertical) -> CGFloat {
    switch vertical {
    case .top:
      // OS already places the banner at the top; keep window origin as-is.
      return windowFrame.origin.y

    case .middle:
      // Center the banner vertically on the visible area, biased up by dockPadding/2
      // so the Dock's presence doesn't visually push the banner off-center.
      let bannerCenterInWindow = bannerFrame.minY + bannerFrame.height / 2
      let visibleCenterAX = (visibleTopAX + visibleBottomAX) / 2
      return visibleCenterAX - bannerCenterInWindow - Constants.dockPadding / 2

    case .bottom:
      // Pin the banner's bottom edge dockPadding above the visible-area bottom.
      let targetBannerBottomAX = visibleBottomAX - Constants.dockPadding
      let bannerBottomInWindow = bannerFrame.maxY
      return targetBannerBottomAX - bannerBottomInWindow
    }
  }
}
