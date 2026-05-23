import Foundation
import Testing

@testable import BannerShiftCore

private func makeSuite() -> UserDefaults {
  let name = "test-\(UUID().uuidString)"
  let suite = UserDefaults(suiteName: name)!
  suite.removePersistentDomain(forName: name)
  return suite
}

@Test func ruleStoreEmptyByDefault() {
  let store = RuleStore(defaults: makeSuite())
  #expect(store.load() == [])
}

@Test func ruleStoreSaveLoadRoundTripPreservesOrder() {
  let suite = makeSuite()
  let store = RuleStore(defaults: suite)
  let rules = [
    Rule(name: "A", appPattern: "Slack", position: .middle),
    Rule(name: "B", appPattern: "Calendar", position: .topRight),
  ]
  store.save(rules)
  let back = RuleStore(defaults: suite).load()
  #expect(back == rules)
  #expect(back.map(\.name) == ["A", "B"])
}

@Test func ruleStoreReturnsEmptyOnCorruptJSON() {
  let suite = makeSuite()
  suite.set(Data("not json".utf8), forKey: RuleStore.key)
  var logged: [String] = []
  let store = RuleStore(defaults: suite, logger: { logged.append($0) })
  #expect(store.load() == [])
  #expect(!logged.isEmpty)
}

@Test func ruleStoreLoadIsCachedAcrossCalls() {
  // perf-001 / quality-012: load() decodes once and caches the result.
  // Verify by mutating the backing UserDefaults blob after the first
  // load: a non-cached implementation would surface the new contents
  // on the next load; the cached implementation must return the
  // previously decoded value.
  let suite = makeSuite()
  let store = RuleStore(defaults: suite)
  let initial = [
    Rule(name: "A", appPattern: "Slack", position: .middle)
  ]
  store.save(initial)

  let first = store.load()
  #expect(first == initial)

  // Mutate the underlying defaults blob behind the store's back. If
  // load() bypasses its cache it will return the mutated rules; the
  // cached implementation must keep returning `initial`.
  let usurper = [
    Rule(name: "Hijacked", appPattern: "X", position: .topLeft),
    Rule(name: "Also", appPattern: "Y", position: .topRight),
  ]
  let mutatedBlob = try! JSONEncoder().encode(usurper)
  suite.set(mutatedBlob, forKey: RuleStore.key)

  let second = store.load()
  #expect(second == initial)
  #expect(second.map(\.name) == ["A"])
}

@Test func ruleStoreSaveUpdatesCache() {
  // Save must refresh the cache so a subsequent load() reflects the
  // newly persisted rules without re-decoding from defaults.
  let suite = makeSuite()
  let store = RuleStore(defaults: suite)
  store.save([Rule(name: "First")])
  _ = store.load()  // prime the cache

  let updated = [Rule(name: "Second"), Rule(name: "Third")]
  store.save(updated)

  // Wipe the backing store to prove load() is reading the cache, not defaults.
  suite.removeObject(forKey: RuleStore.key)

  #expect(store.load() == updated)
}
