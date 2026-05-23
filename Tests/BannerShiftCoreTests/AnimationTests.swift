import Foundation
import Testing

@testable import BannerShiftCore

@Test func animationFourCases() {
  #expect(Animation.allCases.count == 4)
}

@Test func animationRawValuesStable() {
  #expect(Animation.none.rawValue == "none")
  #expect(Animation.slide.rawValue == "slide")
  #expect(Animation.shake.rawValue == "shake")
  #expect(Animation.bounce.rawValue == "bounce")
}

@Test func animationDisplayNames() {
  #expect(Animation.none.displayName == "None")
  #expect(Animation.slide.displayName == "Slide")
  #expect(Animation.shake.displayName == "Shake")
  #expect(Animation.bounce.displayName == "Bounce")
}

@Test func animationCodableRoundTrip() throws {
  for animation in Animation.allCases {
    let data = try JSONEncoder().encode(animation)
    let decoded = try JSONDecoder().decode(Animation.self, from: data)
    #expect(decoded == animation)
  }
}
