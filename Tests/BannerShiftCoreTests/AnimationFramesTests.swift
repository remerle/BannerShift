import CoreGraphics
import Testing

@testable import BannerShiftCore

private let from = CGPoint(x: 0, y: 0)
private let to = CGPoint(x: 100, y: 50)

@Test func noneProducesOneFrameAtTarget() {
  let frames = AnimationFrames.frames(style: .none, from: from, to: to)
  #expect(frames.count == 1)
  #expect(frames[0].point == to)
  #expect(frames[0].timeOffset == 0)
}

@Test func slideStartsFromAndEndsAtTarget() {
  let frames = AnimationFrames.frames(style: .slide, from: from, to: to)
  #expect(frames.first!.point == from)
  #expect(frames.last!.point == to)
  #expect(frames.first!.timeOffset == 0)
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

@Test func shakeStartsAndEndsAtCenter() {
  let frames = AnimationFrames.frames(style: .shake, from: from, to: to)
  #expect(frames.first!.point == to)
  #expect(frames.last!.point == to)
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
  // Image-fidelity guard (plan §7.1): every animation frame must emit
  // an integer-point target so the banner renders crisp throughout the
  // animation, not just at the final settle position. Sweep all styles
  // with off-axis from/to so the sine envelope and ease curve hit
  // fractional intermediates pre-rounding.
  let fromVariants: [CGPoint] = [.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: 13, y: 27)]
  let toVariants: [CGPoint] = [
    CGPoint(x: 100, y: 50),
    CGPoint(x: 333, y: 167),
    CGPoint(x: -55, y: 240),
  ]
  for style in Animation.allCases {
    for fromP in fromVariants {
      for toP in toVariants {
        let frames = AnimationFrames.frames(style: style, from: fromP, to: toP)
        for (i, f) in frames.enumerated() {
          #expect(
            f.point.x == f.point.x.rounded(),
            "non-integer x at frame \(i) for \(style.rawValue) from=\(fromP) to=\(toP)")
          #expect(
            f.point.y == f.point.y.rounded(),
            "non-integer y at frame \(i) for \(style.rawValue) from=\(fromP) to=\(toP)")
        }
      }
    }
  }
}
