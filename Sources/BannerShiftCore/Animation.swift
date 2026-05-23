import Foundation

public enum Animation: String, CaseIterable, Sendable, Codable {
  case none = "none"
  case slide = "slide"
  case shake = "shake"
  case bounce = "bounce"

  public var displayName: String {
    switch self {
    case .none: return "None"
    case .slide: return "Slide"
    case .shake: return "Shake"
    case .bounce: return "Bounce"
    }
  }
}
