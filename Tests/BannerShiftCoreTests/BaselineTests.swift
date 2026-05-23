import CoreGraphics
import Testing

@testable import BannerShiftCore

@Test func baselineHoldsAllThreeFields() {
  let baseline = Baseline(
    originalOrigin: CGPoint(x: 100, y: 200),
    windowFrame: CGRect(x: 100, y: 200, width: 1000, height: 800),
    bannerFrame: CGRect(x: 800, y: 220, width: 360, height: 80)
  )
  #expect(baseline.originalOrigin == CGPoint(x: 100, y: 200))
  #expect(baseline.windowFrame.size.width == 1000)
  #expect(baseline.bannerFrame.origin.x == 800)
}

@Test func baselineEquatable() {
  let lhs = Baseline(
    originalOrigin: .zero,
    windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
    bannerFrame: CGRect(x: 1, y: 1, width: 2, height: 2)
  )
  let rhs = lhs
  #expect(lhs == rhs)
}
