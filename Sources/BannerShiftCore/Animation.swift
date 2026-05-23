import Foundation

/// Motion style applied as a banner is repositioned.
///
/// Encoded as a raw `String` so the persisted form survives reordering
/// of cases. `.none` snaps directly to the target with no animation;
/// `.slide` interpolates from the OS-original origin; `.shake` and
/// `.bounce` oscillate around the target after snapping there first.
public enum Animation: String, CaseIterable, Sendable, Codable {
  case none
  case slide
  case shake
  case bounce

  /// Human-readable label for the rule editor's animation picker.
  public var displayName: String {
    switch self {
    case .none: return "None"
    case .slide: return "Slide"
    case .shake: return "Shake"
    case .bounce: return "Bounce"
    }
  }
}
