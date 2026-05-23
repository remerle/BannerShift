import CoreGraphics
import Testing

@testable import BannerShiftCore

@Test func identicalKeysAreEqual() {
  let lhs = ObserverKey(
    elementID: 0x1000, role: "AXWindow", subrole: "AXSystemDialog",
    size: CGSize(width: 1920, height: 1080))
  let rhs = ObserverKey(
    elementID: 0x1000, role: "AXWindow", subrole: "AXSystemDialog",
    size: CGSize(width: 1920, height: 1080))
  #expect(lhs == rhs)
  #expect(lhs.hashValue == rhs.hashValue)
}

@Test func differentElementIDsDoNotCollide() {
  let lhs = ObserverKey(
    elementID: 0x1000, role: "AXWindow", subrole: "X",
    size: CGSize(width: 1, height: 1))
  let rhs = ObserverKey(
    elementID: 0x2000, role: "AXWindow", subrole: "X",
    size: CGSize(width: 1, height: 1))
  #expect(lhs != rhs)
}

@Test func sameShapeDifferentElementIDsStayDistinct() {
  // The bug we're fixing: two banner windows with identical role/subrole/size
  // but different identity must remain distinct keys.
  var set: Set<ObserverKey> = []
  set.insert(
    ObserverKey(
      elementID: 0xA, role: "AXWindow", subrole: "AXSystemDialog",
      size: CGSize(width: 1920, height: 1080)))
  set.insert(
    ObserverKey(
      elementID: 0xB, role: "AXWindow", subrole: "AXSystemDialog",
      size: CGSize(width: 1920, height: 1080)))
  #expect(set.count == 2)
}

@Test func positionIsExcludedFromKey() {
  // Position changes every time we move a window — must not affect identity.
  // (Two keys built with the same elementID/role/subrole/size are equal regardless of where
  // the window is on screen because position is not part of the key.)
  let lhs = ObserverKey(
    elementID: 0x1000, role: "AXWindow", subrole: "X",
    size: CGSize(width: 1, height: 1))
  let rhs = ObserverKey(
    elementID: 0x1000, role: "AXWindow", subrole: "X",
    size: CGSize(width: 1, height: 1))
  #expect(lhs == rhs)
}
