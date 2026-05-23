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
  public let windowFrame: CGRect
  public let bannerFrame: CGRect
  public let screen: ScreenInfo
  /// AppKit→AX y-flip pivot. Must be the *primary* display's height, not the
  /// chosen display's height. Same-height monitor setups land on the correct
  /// value either way; heterogeneous-height multi-monitor setups will mis-place
  /// banners on the non-primary display if the chosen display's height is used
  /// here.
  public let primaryHeight: CGFloat

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

  /// True iff the AX container window is the full height of the display. This
  /// is the invariant the rest of the math depends on; callers must check it
  /// before trusting `targetOrigin(for:)`. Violations are typically caused by
  /// a macOS update changing the notification UI's window layout.
  public var invariantHolds: Bool {
    windowFrame.size.height == screen.frame.size.height
  }

  /// Computes the integer-snapped target window origin for the given 3x3 cell.
  public func targetOrigin(for position: Position) -> CGPoint {
    let x = horizontalOrigin(for: position.horizontal)
    let y = verticalOrigin(for: position.vertical)
    return CGPoint(x: x.rounded(), y: y.rounded())
  }

  // MARK: - Horizontal

  private func horizontalOrigin(for h: Position.Horizontal) -> CGFloat {
    switch h {
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

  private func verticalOrigin(for v: Position.Vertical) -> CGFloat {
    switch v {
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
