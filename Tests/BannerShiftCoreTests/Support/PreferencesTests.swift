import Foundation
import Testing

@testable import BannerShiftCore

private func makeSuite() throws -> UserDefaults {
  let name = "test-\(UUID().uuidString)"
  // `UserDefaults(suiteName:)` returns nil only for reserved names
  // (empty, "NSGlobalDomain", "NSRegistrationDomain") and our names
  // are UUID-derived, so this should never fail; `#require` surfaces
  // the failure as a clean test issue rather than a crash if it does.
  let suite = try #require(UserDefaults(suiteName: name))
  suite.removePersistentDomain(forName: name)
  return suite
}

@Test func positionDefaultsToTopMiddle() throws {
  let prefs = Preferences(defaults: try makeSuite())
  #expect(prefs.position == .topMiddle)
}

@Test func positionPersistsValidString() throws {
  let suite = try makeSuite()
  let prefs = Preferences(defaults: suite)
  prefs.position = .bottomRight
  #expect(Preferences(defaults: suite).position == .bottomRight)
}

@Test func positionFallsBackOnMalformedString() throws {
  let suite = try makeSuite()
  suite.set("garbage-value", forKey: "selectedPosition")
  let prefs = Preferences(defaults: suite)
  #expect(prefs.position == .topMiddle)
}

@Test func iconHiddenDefaultsToFalse() throws {
  let prefs = Preferences(defaults: try makeSuite())
  #expect(prefs.iconHidden == false)
}

@Test func iconHiddenPersists() throws {
  let suite = try makeSuite()
  let prefs = Preferences(defaults: suite)
  prefs.iconHidden = true
  #expect(Preferences(defaults: suite).iconHidden == true)
}

@Test func debugLoggingDefaultsToFalse() throws {
  let prefs = Preferences(defaults: try makeSuite())
  #expect(prefs.debugLoggingEnabled == false)
}

@Test func debugLoggingIsReadLiveNotCached() throws {
  let suite = try makeSuite()
  let prefs = Preferences(defaults: suite)
  #expect(prefs.debugLoggingEnabled == false)
  suite.set(true, forKey: "debugLoggingEnabled")
  #expect(prefs.debugLoggingEnabled == true)
}

@Test func pinnedPanelOriginDefaultsToNil() throws {
  let prefs = Preferences(defaults: try makeSuite())
  #expect(prefs.pinnedPanelOrigin == nil)
}

@Test func pinnedPanelOriginRoundTrips() throws {
  let suite = try makeSuite()
  let prefs = Preferences(defaults: suite)
  prefs.pinnedPanelOrigin = CGPoint(x: 137.5, y: -42)
  let reread = try #require(Preferences(defaults: suite).pinnedPanelOrigin)
  #expect(reread.x == 137.5)
  #expect(reread.y == -42)
}

@Test func pinnedPanelOriginSettingNilClearsStoredValue() throws {
  let suite = try makeSuite()
  let prefs = Preferences(defaults: suite)
  prefs.pinnedPanelOrigin = CGPoint(x: 10, y: 20)
  prefs.pinnedPanelOrigin = nil
  #expect(Preferences(defaults: suite).pinnedPanelOrigin == nil)
  #expect(suite.string(forKey: "pinnedPanelOrigin") == nil)
}

@Test func pinnedPanelOriginFallsBackOnMalformedString() throws {
  // External / stale values must not crash or yield a bogus point.
  for garbage in ["garbage", "1", "1,2,3", "x,y", ""] {
    let suite = try makeSuite()
    suite.set(garbage, forKey: "pinnedPanelOrigin")
    #expect(
      Preferences(defaults: suite).pinnedPanelOrigin == nil,
      "malformed origin \"\(garbage)\" must parse as nil")
  }
}
