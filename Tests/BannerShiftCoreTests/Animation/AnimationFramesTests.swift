import CoreGraphics
import Testing

@testable import BannerShiftCore

private let to = CGPoint(x: 100, y: 50)

@Test func noneProducesOneFrameAtTarget() {
  let frames = AnimationFrames.frames(style: .none, to: to)
  #expect(frames.count == 1)
  #expect(frames[0].point == to)
  #expect(frames[0].timeOffset == 0)
}

@Test func shakeStartsAndEndsAtCenter() throws {
  let frames = AnimationFrames.frames(style: .shake, to: to)
  let first = try #require(frames.first)
  let last = try #require(frames.last)
  #expect(first.point == to)
  #expect(last.point == to)
}

@Test func bounceVariesYNotX() {
  let frames = AnimationFrames.frames(style: .bounce, to: to)
  let xs = Set(frames.map { $0.point.x })
  let ys = Set(frames.map { $0.point.y })
  #expect(xs.count == 1)
  #expect(ys.count > 1)
}

@Test func shakeVariesXNotY() {
  let frames = AnimationFrames.frames(style: .shake, to: to)
  let xs = Set(frames.map { $0.point.x })
  let ys = Set(frames.map { $0.point.y })
  #expect(ys.count == 1)
  #expect(xs.count > 1)
}

@Test func bounceHopsUpwardAndRepeats() {
  let frames = AnimationFrames.frames(style: .bounce, to: to)
  // One-directional: the banner only ever rises above its resting spot (up is
  // a smaller y in AX top-left coordinates) and returns to it, never below.
  #expect(frames.allSatisfy { $0.point.y <= to.y })
  #expect(frames.contains { $0.point.y < to.y })
  // Continuous: it returns to the resting y once per hop — several times —
  // rather than a single damped wobble that settles immediately.
  let floorTouches = frames.filter { $0.point.y == to.y }.count
  #expect(floorTouches >= 3)
}

@Test func shakeHasPausesBetweenBursts() {
  let frames = AnimationFrames.frames(style: .shake, to: to)
  let times = frames.map { $0.timeOffset }.sorted()
  let maxGap = zip(times.dropFirst(), times).map { $0 - $1 }.max() ?? 0
  // The largest gap between consecutive frames is the still pause between two
  // bursts, far larger than the in-burst frame interval (~burstDuration/fps).
  #expect(maxGap > 0.2)
}

@Test func settleFrameIsIntegerSnappedForFractionalCenter() {
  // Both styles append an explicit settle frame at `center`. It must snap to
  // integer points even when the runtime target carries a sub-pixel component,
  // honoring the "every frame is integer-snapped" contract. Cover the case
  // explicitly with a fractional `to`.
  let fractionalTo = CGPoint(x: 100.5, y: 50.5)
  for style in [Animation.shake, Animation.bounce] {
    let frames = AnimationFrames.frames(style: style, to: fractionalTo)
    let last = frames.last
    #expect(last?.point.x == last?.point.x.rounded())
    #expect(last?.point.y == last?.point.y.rounded())
  }
}

@Test func everyFrameLandsOnIntegerPoints() {
  // Image-fidelity guard: every animation frame must emit an integer-point
  // target so the banner renders crisp throughout the animation, not just
  // at the final settle position. Sweep the oscillating styles with off-axis
  // targets so the sine envelope and arc hit fractional intermediates
  // pre-rounding. Targets are integers because production targets arrive
  // pre-snapped from PositionCalculator and `.none` passes `to` through
  // unrounded; fractional-center snapping for shake/bounce is covered by
  // `settleFrameIsIntegerSnappedForFractionalCenter`.
  let toVariants: [CGPoint] = [
    CGPoint(x: 100, y: 50),
    CGPoint(x: 333, y: 167),
    CGPoint(x: -55, y: 240),
  ]
  for style in Animation.allCases {
    for toPoint in toVariants {
      let frames = AnimationFrames.frames(style: style, to: toPoint)
      for (index, frame) in frames.enumerated() {
        let context = "frame \(index) for \(style.rawValue) to=\(toPoint)"
        #expect(
          frame.point.x == frame.point.x.rounded(),
          "non-integer x at \(context)")
        #expect(
          frame.point.y == frame.point.y.rounded(),
          "non-integer y at \(context)")
      }
    }
  }
}
