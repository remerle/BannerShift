import Foundation
import Testing

@testable import BannerShiftCore

private func makeSuite() -> UserDefaults {
  let name = "test-\(UUID().uuidString)"
  let suite = UserDefaults(suiteName: name)!
  suite.removePersistentDomain(forName: name)
  return suite
}

@Test func positionDefaultsToTopMiddle() {
  let prefs = Preferences(defaults: makeSuite())
  #expect(prefs.position == .topMiddle)
}

@Test func positionPersistsValidString() {
  let suite = makeSuite()
  let prefs = Preferences(defaults: suite)
  prefs.position = .bottomRight
  #expect(Preferences(defaults: suite).position == .bottomRight)
}

@Test func positionFallsBackOnMalformedString() {
  let suite = makeSuite()
  suite.set("garbage-value", forKey: "selectedPosition")
  let prefs = Preferences(defaults: suite)
  #expect(prefs.position == .topMiddle)
}

@Test func iconHiddenDefaultsToFalse() {
  let prefs = Preferences(defaults: makeSuite())
  #expect(prefs.iconHidden == false)
}

@Test func iconHiddenPersists() {
  let suite = makeSuite()
  let prefs = Preferences(defaults: suite)
  prefs.iconHidden = true
  #expect(Preferences(defaults: suite).iconHidden == true)
}

@Test func debugLoggingDefaultsToFalse() {
  let prefs = Preferences(defaults: makeSuite())
  #expect(prefs.debugLoggingEnabled == false)
}

@Test func debugLoggingIsReadLiveNotCached() {
  let suite = makeSuite()
  let prefs = Preferences(defaults: suite)
  #expect(prefs.debugLoggingEnabled == false)
  suite.set(true, forKey: "debugLoggingEnabled")
  #expect(prefs.debugLoggingEnabled == true)
}
