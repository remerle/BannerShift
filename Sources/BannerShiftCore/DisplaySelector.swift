import CoreGraphics

public struct DisplaySelector {
  public let screens: [ScreenInfo]

  public init(screens: [ScreenInfo]) {
    self.screens = screens
  }

  private var primary: ScreenInfo? {
    screens.first(where: { $0.isPrimary }) ?? screens.first
  }

  /// Convert an AX-coordinate point (top-left origin) to an AppKit point and
  /// find the first screen whose frame contains it.
  ///
  /// Fallback chain when no screen contains the point:
  ///   1. matched screen
  ///   2. `activeScreenFallback` if provided
  ///   3. the primary screen
  ///
  /// Returns nil **only** when `screens` is empty. A non-nil return is
  /// guaranteed whenever at least one screen was passed to the initializer.
  public func screenContaining(
    axPoint: CGPoint,
    activeScreenFallback: ScreenInfo? = nil
  ) -> ScreenInfo? {
    guard let primary = primary else { return nil }
    // Spec §20.4. AX coordinates are top-left, anchored at the primary
    // display's top-left. Convert an AppKit (bottom-left, primary-anchored)
    // y to AX y via `primary.frame.height - appkit_y`. PositionCalculator
    // uses the same pivot for the same reason. Using `frame.height` rather
    // than `frame.maxY` is valid because macOS guarantees the primary
    // display's AppKit origin is (0, 0); on heterogeneous-height multi-monitor
    // setups only the primary height gives the correct conversion.
    let appKitY = primary.frame.height - axPoint.y
    let appKitPoint = CGPoint(x: axPoint.x, y: appKitY)
    if let match = screens.first(where: { $0.frame.contains(appKitPoint) }) {
      return match
    }
    return activeScreenFallback ?? self.primary
  }
}
