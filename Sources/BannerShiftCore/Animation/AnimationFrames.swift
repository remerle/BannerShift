import CoreGraphics
import Foundation

/// Pure function from `(style, from, to, fps)` to a schedule of
/// timed window-origin samples.
///
/// Side-effect-free so the math can be unit-tested without timers; the
/// executable side schedules the points via `Animator`. Every emitted
/// frame is snapped to integer points so the banner renders crisply
/// throughout the animation, not just at the final settle position.
/// Sub-pixel positions on intermediate frames produce blurry, jittery
/// motion even though the final landing point looks correct.
public enum AnimationFrames {
  /// One sample in the animation schedule: a target window origin and
  /// the time offset (from animation start) at which to apply it.
  public struct Frame: Equatable, Sendable {
    /// Seconds from animation start at which `point` should be written
    /// to the AX position attribute.
    public let timeOffset: TimeInterval

    /// Integer-snapped window origin in AX coordinates.
    public let point: CGPoint

    /// Direct memberwise initializer; the type carries no derived
    /// state, so the assignment is the whole construction.
    public init(timeOffset: TimeInterval, point: CGPoint) {
      self.timeOffset = timeOffset
      self.point = point
    }
  }

  /// Generates the sequence of (timeOffset, point) frames the
  /// animation driver should schedule.
  ///
  /// Every style begins and ends at `to` — the banner's resting target.
  /// `.shake` and `.bounce` oscillate around it and settle back, so there
  /// is no separate starting origin to interpolate from. The math is
  /// coordinate-system-agnostic, but all production callers pass AX
  /// coordinates (top-left origin) read from `kAXPositionAttribute`, and the
  /// produced points are written back via `kAXPositionAttribute` in
  /// `Animator.set`, so the convention is AX.
  ///
  /// - Parameters:
  ///   - style: Which animation curve to use.
  ///   - to: Target window origin (AX coordinates, top-left origin).
  ///   - fps: Target frame rate. Higher fps yields more intermediate
  ///     samples for a smoother animation at the cost of more AX writes.
  /// - Returns: Frames in ascending `timeOffset` order, each carrying
  ///   an integer-snapped target origin. `.none` returns a single
  ///   zero-offset frame at `to`; the others return a sweep.
  public static func frames(
    style: Animation,
    to: CGPoint,
    fps: Int = 60
  ) -> [Frame] {
    switch style {
    case .none:
      return [Frame(timeOffset: 0, point: to)]

    case .shake:
      return shake(center: to, amplitude: 10, fps: fps)

    case .bounce:
      return bounce(center: to, height: 14, fps: fps)
    }
  }

  // MARK: - Private

  /// Repeated upward hops in a gravity-like arc: the banner springs up from
  /// its resting spot and falls back, over and over.
  ///
  /// Unlike `shake`, the motion is one-directional — the banner only ever
  /// rises above its resting point and returns to it (the resting spot is the
  /// "floor"), which reads as bouncing rather than vibrating. Each hop follows
  /// a `4t(1-t)` parabola, so it moves fast at the floor and lingers at the
  /// apex like a tossed ball. The amplitude stays constant across hops, so it
  /// bounces continuously rather than damping out.
  private static func bounce(center: CGPoint, height: CGFloat, fps: Int) -> [Frame] {
    let hopDuration = 0.42
    let hops = 6
    let perHop = max(1, Int(round(hopDuration * Double(fps))))
    var out: [Frame] = []
    out.reserveCapacity(hops * perHop + 1)
    for hop in 0..<hops {
      for step in 0..<perHop {
        let progress = Double(step) / Double(perHop)  // 0..<1 within this hop
        let arc = 4.0 * progress * (1.0 - progress)  // 0 → 1 → 0, apex at 0.5
        // Up is negative y in AX top-left coordinates.
        let point = CGPoint(
          x: center.x.rounded(),
          y: (center.y - height * CGFloat(arc)).rounded()
        )
        out.append(Frame(timeOffset: (Double(hop) + progress) * hopDuration, point: point))
      }
    }
    out.append(settleFrame(at: center, timeOffset: Double(hops) * hopDuration))
    return out
  }

  /// Bursts of horizontal oscillation separated by still pauses: shake,
  /// pause, shake, pause.
  ///
  /// Each burst is a full-amplitude sine — no decaying envelope — so the
  /// shake stays lively start to finish, then the banner holds at its resting
  /// spot through the pause (an empty stretch of the schedule) before the next
  /// burst. Horizontal-only, symmetric about the resting spot.
  private static func shake(center: CGPoint, amplitude: CGFloat, fps: Int) -> [Frame] {
    let burstDuration = 0.30
    let pauseDuration = 0.40
    let cyclesPerBurst = 3.0
    let bursts = 3
    let perBurst = max(1, Int(round(burstDuration * Double(fps))))
    var out: [Frame] = []
    var clock = 0.0
    for _ in 0..<bursts {
      for step in 0...perBurst {
        let progress = Double(step) / Double(perBurst)  // 0...1 within this burst
        let displacement = sin(2.0 * .pi * cyclesPerBurst * progress)
        let point = CGPoint(
          x: (center.x + amplitude * CGFloat(displacement)).rounded(),
          y: center.y.rounded()
        )
        out.append(Frame(timeOffset: clock + progress * burstDuration, point: point))
      }
      clock += burstDuration
      // Hold at the resting spot through the pause: no frames are emitted in
      // the gap, so the last-written position stands until the next burst.
      out.append(settleFrame(at: center, timeOffset: clock))
      clock += pauseDuration
    }
    return out
  }

  /// A frame at the integer-snapped resting point.
  ///
  /// Snapping `center` (rather than emitting it raw) preserves the
  /// "every frame is integer-snapped" contract even when the target origin
  /// carries a sub-pixel component from AppKit geometry.
  private static func settleFrame(at center: CGPoint, timeOffset: TimeInterval) -> Frame {
    Frame(timeOffset: timeOffset, point: CGPoint(x: center.x.rounded(), y: center.y.rounded()))
  }
}
