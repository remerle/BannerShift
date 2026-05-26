import CoreGraphics
import Testing

@testable import BannerShiftCore

@Test func snapshotFirstSightHoldsGeometryAndPosition() {
  let snapshot = BannerWindowSnapshot(
    originalOrigin: CGPoint(x: 100, y: 200),
    windowFrame: CGRect(x: 100, y: 200, width: 1000, height: 800),
    bannerFrame: CGRect(x: 800, y: 220, width: 360, height: 80),
    position: .bottomRight
  )
  #expect(snapshot.originalOrigin == CGPoint(x: 100, y: 200))
  #expect(snapshot.windowFrame.size.width == 1000)
  #expect(snapshot.bannerFrame.origin.x == 800)
  #expect(snapshot.position == .bottomRight)
  // Animation and ruleName stay nil until the post-move async resolve fills
  // them in; equality still works on a first-sight snapshot.
  #expect(snapshot.animation == nil)
  #expect(snapshot.ruleName == nil)
}

@Test func snapshotResolutionIsMutable() {
  // The async resolve writes back animation and ruleName; verify the snapshot
  // tolerates the in-place update used by `BannerMover.resolveAndFollowUp`.
  var snapshot = BannerWindowSnapshot(
    originalOrigin: .zero,
    windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
    bannerFrame: CGRect(x: 1, y: 1, width: 2, height: 2),
    position: .topMiddle
  )
  snapshot.animation = .shake
  snapshot.ruleName = "Slack DMs"
  #expect(snapshot.animation == .shake)
  #expect(snapshot.ruleName == "Slack DMs")
}

@Test func snapshotEquatable() {
  let lhs = BannerWindowSnapshot(
    originalOrigin: .zero,
    windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
    bannerFrame: CGRect(x: 1, y: 1, width: 2, height: 2),
    position: .topMiddle,
    animation: .none,
    ruleName: "(default)"
  )
  let rhs = lhs
  #expect(lhs == rhs)
}

@Test func snapshotInequalWhenPositionDiffers() {
  // Position participates in equality, so two snapshots with the same
  // geometry but different positions are distinct.
  let base = BannerWindowSnapshot(
    originalOrigin: .zero,
    windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
    bannerFrame: CGRect(x: 1, y: 1, width: 2, height: 2),
    position: .topMiddle
  )
  let differentPosition = BannerWindowSnapshot(
    originalOrigin: .zero,
    windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
    bannerFrame: CGRect(x: 1, y: 1, width: 2, height: 2),
    position: .bottomLeft
  )
  #expect(base != differentPosition)
}
