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
  /// `from` and `to` must be in the same coordinate space; the
  /// function does not transform between spaces. The math is
  /// coordinate-system-agnostic in practice (linear interpolation
  /// between two opaque points), but all production callers pass AX
  /// coordinates (top-left origin) read from `kAXPositionAttribute`,
  /// and the produced points are written back via `kAXPositionAttribute`
  /// in `Animator.set`, so the convention is AX.
  ///
  /// - Parameters:
  ///   - style: Which animation curve to use.
  ///   - from: Starting window origin (AX coordinates, top-left origin).
  ///   - to: Target window origin (AX coordinates, top-left origin).
  ///   - fps: Target frame rate. Higher fps yields more intermediate
  ///     samples for a smoother animation at the cost of more AX writes.
  /// - Returns: Frames in ascending `timeOffset` order, each carrying
  ///   an integer-snapped target origin. `.none` returns a single
  ///   zero-offset frame at `to`; the others return a sweep.
  public static func frames(
    style: Animation,
    from: CGPoint,
    to: CGPoint,
    fps: Int = 60
  ) -> [Frame] {
    switch style {
    case .none:
      return [Frame(timeOffset: 0, point: to)]

    case .slide:
      return slide(from: from, to: to, duration: 0.200, fps: fps)

    case .shake:
      return oscillate(center: to, ax: 10, ay: 0, duration: 0.250, fps: fps)

    case .bounce:
      return oscillate(center: to, ax: 0, ay: 10, duration: 0.250, fps: fps)
    }
  }

  // MARK: - Private

  private static func slide(
    from: CGPoint, to: CGPoint,
    duration: TimeInterval, fps: Int
  ) -> [Frame] {
    let count = max(1, Int(round(duration * Double(fps))))
    var out: [Frame] = []
    out.reserveCapacity(count + 1)
    for step in 0...count {
      let progress = Double(step) / Double(count)
      let eased = 1 - pow(1 - progress, 3)
      let point = CGPoint(
        x: (from.x + (to.x - from.x) * CGFloat(eased)).rounded(),
        y: (from.y + (to.y - from.y) * CGFloat(eased)).rounded()
      )
      out.append(Frame(timeOffset: progress * duration, point: point))
    }
    return out
  }

  private static func oscillate(
    center: CGPoint, ax: CGFloat, ay: CGFloat,
    duration: TimeInterval, fps: Int
  ) -> [Frame] {
    let count = max(1, Int(round(duration * Double(fps))))
    var out: [Frame] = []
    out.reserveCapacity(count + 1)
    let cycles = 3.0
    for step in 0...count {
      let progress = Double(step) / Double(count)
      let envelope = 1.0 - progress
      let displacement = sin(2.0 * .pi * cycles * progress) * envelope
      let point = CGPoint(
        x: (center.x + ax * CGFloat(displacement)).rounded(),
        y: (center.y + ay * CGFloat(displacement)).rounded()
      )
      out.append(Frame(timeOffset: progress * duration, point: point))
    }
    if out.last?.point != center {
      out.append(Frame(timeOffset: duration, point: center))
    }
    return out
  }
}
