import Foundation

/// Motion style applied as a banner is repositioned.
///
/// Encoded as a raw `String` so the persisted form survives reordering
/// of cases. `.none` snaps directly to the target with no animation;
/// `.shake` snaps to the target then vibrates horizontally in bursts
/// separated by pauses; `.bounce` snaps to the target then springs upward
/// in repeated gravity-like hops.
public enum Animation: String, CaseIterable, Sendable, Codable {
  case none
  case shake
  case bounce

  /// Human-readable label for the rule editor's animation picker.
  public var displayName: String {
    switch self {
    case .none: return "None"
    case .shake: return "Shake"
    case .bounce: return "Bounce"
    }
  }
}
