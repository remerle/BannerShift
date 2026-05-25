import CoreGraphics

/// Identity of an AX window, used as the de-duplication key for the AX
/// observer's registered-windows set.
///
/// Pointer-identity alone (`elementID`) is enough to dedupe within a
/// single notification UI process lifetime, but `role`, `subrole`, and
/// `size` are kept as part of the key so a window whose AX shape has
/// changed (rare, but possible across OS updates) is re-registered
/// rather than mis-coalesced with a stale entry.
public struct AXWindowKey: Hashable, Sendable {
  /// Stable identity of the underlying AX element, derived from `CFHash`.
  ///
  /// It must be `CFHash`-based, not the boxed pointer address: `kAXWindows`
  /// hands back a fresh `AXUIElement` box on every query, so the raw pointer
  /// differs pass-to-pass for the same window. `CFHash` is consistent with
  /// `CFEqual` and stays stable across those copies within a single
  /// notification UI process lifetime (matching `BannerMover.elementID`).
  /// Tearing down and recreating that process invalidates every prior
  /// `elementID`, and the keyed maps in `BannerMover` must be cleared then.
  public let elementID: UInt64

  /// AX role of the registered element (e.g. `AXWindow`).
  public let role: String

  /// AX subrole of the registered element (e.g. one of
  /// `Constants.bannerSubroles`).
  public let subrole: String

  /// Size of the element at registration time, in AX points.
  ///
  /// Part of the key so a structural reshape produces a new key rather
  /// than a stale match against the prior shape.
  public let size: CGSize

  /// Constructs the key from the four components captured at AX
  /// registration time.
  public init(elementID: UInt64, role: String, subrole: String, size: CGSize) {
    self.elementID = elementID
    self.role = role
    self.subrole = subrole
    self.size = size
  }
}
