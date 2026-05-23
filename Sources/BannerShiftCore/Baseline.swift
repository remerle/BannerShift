import CoreGraphics

public struct Baseline: Equatable, Sendable {
  public let originalOrigin: CGPoint
  public let windowFrame: CGRect
  public let bannerFrame: CGRect

  public init(originalOrigin: CGPoint, windowFrame: CGRect, bannerFrame: CGRect) {
    self.originalOrigin = originalOrigin
    self.windowFrame = windowFrame
    self.bannerFrame = bannerFrame
  }
}
