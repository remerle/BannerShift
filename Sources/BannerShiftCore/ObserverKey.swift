import CoreGraphics

public struct ObserverKey: Hashable, Sendable {
  /// Stable opaque address of the underlying AX element. `AXUIElement`
  /// pointer identity is stable across attribute changes (including geometry
  /// moves) within a single notification UI process lifetime; tearing down
  /// and recreating that process invalidates every prior `elementID` and the
  /// keyed maps in `BannerMover` must be cleared at that point.
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
