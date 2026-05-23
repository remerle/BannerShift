import CoreGraphics
import Testing

@testable import BannerShiftCore

private let from = CGPoint.zero
private let to = CGPoint(x: 100, y: 50)

@Test func noneProducesOneFrameAtTarget() {
  let frames = AnimationFrames.frames(style: .none, from: from, to: to)
  #expect(frames.count == 1)
  #expect(frames[0].point == to)
  #expect(frames[0].timeOffset == 0)
}

@Test func slideStartsFromAndEndsAtTarget() throws {
  let frames = AnimationFrames.frames(style: .slide, from: from, to: to)
  let first = try #require(frames.first)
  let last = try #require(frames.last)
  #expect(first.point == from)
  #expect(last.point == to)
  #expect(first.timeOffset == 0)
}

@Test func slideFrameCountTracksFps() {
  let f30 = AnimationFrames.frames(style: .slide, from: from, to: to, fps: 30)
  let f60 = AnimationFrames.frames(style: .slide, from: from, to: to, fps: 60)
  #expect(f60.count > f30.count)
}

@Test func slideTimeOffsetsSorted() {
  let frames = AnimationFrames.frames(style: .slide, from: from, to: to)
  let ts = frames.map { $0.timeOffset }
  #expect(ts == ts.sorted())
}

@Test func shakeStartsAndEndsAtCenter() throws {
  let frames = AnimationFrames.frames(style: .shake, from: from, to: to)
  let first = try #require(frames.first)
  let last = try #require(frames.last)
  #expect(first.point == to)
  #expect(last.point == to)
}

@Test func bounceVariesYNotX() {
  let frames = AnimationFrames.frames(style: .bounce, from: from, to: to)
  let xs = Set(frames.map { $0.point.x })
  let ys = Set(frames.map { $0.point.y })
  #expect(xs.count == 1)
  #expect(ys.count > 1)
}

@Test func shakeVariesXNotY() {
  let frames = AnimationFrames.frames(style: .shake, from: from, to: to)
  let xs = Set(frames.map { $0.point.x })
  let ys = Set(frames.map { $0.point.y })
  #expect(ys.count == 1)
  #expect(xs.count > 1)
}

@Test func everyFrameLandsOnIntegerPoints() {
  // Image-fidelity guard: every animation frame must emit an integer-point
  // target so the banner renders crisp throughout the animation, not just
  // at the final settle position. Sweep all styles with off-axis from/to
  // so the sine envelope and ease curve hit fractional intermediates
  // pre-rounding.
  let fromVariants: [CGPoint] = [.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 13, y: 27)]
  let toVariants: [CGPoint] = [
    CGPoint(x: 100, y: 50),
    CGPoint(x: 333, y: 167),
    CGPoint(x: -55, y: 240),
  ]
  for style in Animation.allCases {
    for fromPoint in fromVariants {
      for toPoint in toVariants {
        let frames = AnimationFrames.frames(style: style, from: fromPoint, to: toPoint)
        for (index, frame) in frames.enumerated() {
          let context = "frame \(index) for \(style.rawValue) from=\(fromPoint) to=\(toPoint)"
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
}
