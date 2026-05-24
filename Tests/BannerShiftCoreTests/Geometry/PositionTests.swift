import Testing

@testable import BannerShiftCore

@Test func positionHasNineCases() {
  #expect(Position.allCases.count == 9)
}

@Test func positionRawValueRoundTrips() {
  for position in Position.allCases {
    #expect(Position(rawValue: position.rawValue) == position)
  }
}

@Test func positionRawValuesAreStable() {
  // These are persisted in UserDefaults; do not change them.
  #expect(Position.topLeft.rawValue == "top-left")
  #expect(Position.topMiddle.rawValue == "top-middle")
  #expect(Position.topRight.rawValue == "top-right")
  #expect(Position.middleLeft.rawValue == "middle-left")
  #expect(Position.middle.rawValue == "middle")
  #expect(Position.middleRight.rawValue == "middle-right")
  #expect(Position.bottomLeft.rawValue == "bottom-left")
  #expect(Position.bottomMiddle.rawValue == "bottom-middle")
  #expect(Position.bottomRight.rawValue == "bottom-right")
}

@Test func positionDisplayNamesAreHuman() {
  #expect(Position.topRight.displayName == "Top Right")
  #expect(Position.middle.displayName == "Middle")
  #expect(Position.bottomLeft.displayName == "Bottom Left")
}

@Test func positionHorizontalAndVertical() {
  #expect(Position.topRight.horizontal == .right)
  #expect(Position.topRight.vertical == .top)
  #expect(Position.middle.horizontal == .center)
  #expect(Position.middle.vertical == .middle)
  #expect(Position.bottomLeft.horizontal == .left)
  #expect(Position.bottomLeft.vertical == .bottom)
}
