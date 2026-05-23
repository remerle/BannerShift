import Foundation

public enum Position: String, CaseIterable, Sendable, Codable {
  case topLeft = "top-left"
  case topMiddle = "top-middle"
  case topRight = "top-right"
  case middleLeft = "middle-left"
  case middle = "middle"
  case middleRight = "middle-right"
  case bottomLeft = "bottom-left"
  case bottomMiddle = "bottom-middle"
  case bottomRight = "bottom-right"

  public enum Horizontal: Sendable { case left, center, right }
  public enum Vertical: Sendable { case top, middle, bottom }

  public var horizontal: Horizontal {
    switch self {
    case .topLeft, .middleLeft, .bottomLeft: return .left
    case .topMiddle, .middle, .bottomMiddle: return .center
    case .topRight, .middleRight, .bottomRight: return .right
    }
  }

  public var vertical: Vertical {
    switch self {
    case .topLeft, .topMiddle, .topRight: return .top
    case .middleLeft, .middle, .middleRight: return .middle
    case .bottomLeft, .bottomMiddle, .bottomRight: return .bottom
    }
  }

  public var displayName: String {
    switch self {
    case .topLeft: return "Top Left"
    case .topMiddle: return "Top Middle"
    case .topRight: return "Top Right"
    case .middleLeft: return "Middle Left"
    case .middle: return "Middle"
    case .middleRight: return "Middle Right"
    case .bottomLeft: return "Bottom Left"
    case .bottomMiddle: return "Bottom Middle"
    case .bottomRight: return "Bottom Right"
    }
  }
}
