import CoreGraphics

public struct ScreenInfo: Equatable, Sendable {
  /// AppKit-space frame (bottom-left origin, points).
  public let frame: CGRect
  /// AppKit-space visible frame (excludes menu bar and Dock).
  public let visibleFrame: CGRect
  /// True if this is the screen at index 0 of `NSScreen.screens`.
  public let isPrimary: Bool

  public init(frame: CGRect, visibleFrame: CGRect, isPrimary: Bool) {
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.isPrimary = isPrimary
  }
}
