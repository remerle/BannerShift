import CoreGraphics

/// Pure-data snapshot of one display, taken from `NSScreen` at the
/// start of a reposition pass.
///
/// Decoupling the math from `NSScreen` lets `PositionCalculator` and
/// `DisplaySelector` be fully unit-tested without an AppKit dependency
/// and without depending on the host machine's actual display layout.
public struct ScreenInfo: Equatable, Sendable {
  /// AppKit-space frame (bottom-left origin, points).
  public let frame: CGRect

  /// AppKit-space visible frame (excludes the menu bar and Dock).
  public let visibleFrame: CGRect

  /// True if this is the screen at index 0 of `NSScreen.screens`.
  ///
  /// The primary screen's height is the y-flip pivot used to convert
  /// between AppKit and AX coordinates across the whole virtual desktop.
  public let isPrimary: Bool

  /// Stores the geometry needed by the reposition math.
  public init(frame: CGRect, visibleFrame: CGRect, isPrimary: Bool) {
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.isPrimary = isPrimary
  }
}
