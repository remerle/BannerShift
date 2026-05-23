import CoreGraphics
import Foundation

/// Pure function from `(style, from, to, fps)` to an array of `(timeOffset, point)`
/// frames. Side-effect-free so the math can be unit-tested without timers. See
/// spec §22.
///
/// Every emitted frame is snapped to integer points (plan §7.1 fidelity guard)
/// so the banner renders crisply throughout the animation, not just at the
/// final settle position.
public enum AnimationFrames {
  public struct Frame: Equatable, Sendable {
    public let timeOffset: TimeInterval
    public let point: CGPoint

    public init(timeOffset: TimeInterval, point: CGPoint) {
      self.timeOffset = timeOffset
      self.point = point
    }
  }

  /// Generates the sequence of (timeOffset, point) frames the animation driver
  /// should schedule. `from` is the starting origin; `to` is the settle origin.
  ///
  /// `from` and `to` must be in the same coordinate space; the function does
  /// not transform between spaces. The math is coordinate-system-agnostic in
  /// practice (linear interpolation between two opaque points), but all
  /// production callers pass AX coordinates (top-left origin) read from
  /// `kAXPositionAttribute`, and the produced points are written back via
  /// `kAXPositionAttribute` in `Animator.set`, so the convention is AX.
  ///
  /// - Parameters:
  ///   - style: Which animation curve to use.
  ///   - from: Starting window origin (AX coordinates, top-left origin).
  ///   - to: Target window origin (AX coordinates, top-left origin).
  ///   - fps: Target frame rate. Higher fps -> more intermediate samples.
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
    for i in 0...count {
      let t = Double(i) / Double(count)
      let eased = 1 - pow(1 - t, 3)
      let p = CGPoint(
        x: (from.x + (to.x - from.x) * CGFloat(eased)).rounded(),
        y: (from.y + (to.y - from.y) * CGFloat(eased)).rounded()
      )
      out.append(Frame(timeOffset: t * duration, point: p))
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
    for i in 0...count {
      let t = Double(i) / Double(count)
      let envelope = 1.0 - t
      let s = sin(2.0 * .pi * cycles * t) * envelope
      let p = CGPoint(
        x: (center.x + ax * CGFloat(s)).rounded(),
        y: (center.y + ay * CGFloat(s)).rounded()
      )
      out.append(Frame(timeOffset: t * duration, point: p))
    }
    if out.last?.point != center {
      out.append(Frame(timeOffset: duration, point: center))
    }
    return out
  }
}
