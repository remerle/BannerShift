import CoreGraphics

public struct ObserverKey: Hashable, Sendable {
  /// Stable opaque address of the underlying AX element. Pointer identity
  /// for AXUIElement is stable across attribute changes (incl. moves)
  /// within a single notification UI process lifetime (plan §8, §20.5).
  public let elementID: UInt64
  public let role: String
  public let subrole: String
  public let size: CGSize

  public init(elementID: UInt64, role: String, subrole: String, size: CGSize) {
    self.elementID = elementID
    self.role = role
    self.subrole = subrole
    self.size = size
  }
}
