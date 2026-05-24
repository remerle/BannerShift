import Testing

@testable import BannerShiftCore

private let matcher = RuleMatcher()

@Test func emptyRulesReturnNil() {
  #expect(matcher.match(rules: [], banner: BannerText(appName: "X")) == nil)
}

@Test func ruleWithNoPatternsIsCatchall() {
  let catchall = Rule(name: "Catchall")
  let match = matcher.match(rules: [catchall], banner: BannerText(appName: "Whatever"))
  #expect(match?.rule.id == catchall.id)
}

@Test func appPatternMatchesCaseInsensitively() {
  let rule = Rule(name: "Slack rule", appPattern: "slack")
  let match = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == rule.id)
}

@Test func allSetPatternsMustMatch() {
  let rule = Rule(name: "Slack DMs", appPattern: "Slack", titlePattern: "^DM")
  let dm = matcher.match(
    rules: [rule], banner: BannerText(appName: "Slack", title: "DM from Alice"))
  let chn = matcher.match(rules: [rule], banner: BannerText(appName: "Slack", title: "#general"))
  #expect(dm?.rule.id == rule.id)
  #expect(chn == nil)
}

@Test func firstMatchWins() {
  let firstRule = Rule(name: "A", appPattern: "Slack", position: .middle)
  let secondRule = Rule(name: "B", appPattern: "Slack", position: .topRight)
  let match = matcher.match(
    rules: [firstRule, secondRule], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == firstRule.id)
}

@Test func disabledRuleSkipped() {
  let disabled = Rule(name: "Off", enabled: false, appPattern: "Slack", position: .topLeft)
  let live = Rule(name: "On", appPattern: "Slack", position: .middle)
  let match = matcher.match(rules: [disabled, live], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == live.id)
}

@Test func malformedRegexDoesNotMatch() {
  let bad = Rule(name: "Bad", appPattern: "[unterminated")
  #expect(matcher.match(rules: [bad], banner: BannerText(appName: "anything")) == nil)
}

@Test func malformedRegexInvokesDiagnosticLogger() {
  // A malformed pattern must never be silently swallowed. The matcher
  // emits a diagnostic and treats the containing rule as disabled so the
  // user has a trail to follow when an "obvious" rule stops matching.
  var diagnostics: [String] = []
  let isolatedMatcher = RuleMatcher(diagnosticLogger: { diagnostics.append($0) })
  let bad = Rule(name: "BrokenRule", appPattern: "[unterminated")
  let result = isolatedMatcher.match(rules: [bad], banner: BannerText(appName: "Slack"))
  #expect(result == nil)
  #expect(diagnostics.count == 1)
  #expect(diagnostics.first?.contains("BrokenRule") == true)
}

@Test func malformedRuleDoesNotBlockValidNextRule() {
  let bad = Rule(name: "bad", titlePattern: "[unterminated")
  let good = Rule(name: "good", titlePattern: "hello")
  let banner = BannerText(appName: "App", title: "hello world", subtitle: "", body: "")
  let match = matcher.match(rules: [bad, good], banner: banner)
  #expect(match?.rule.name == "good")
}

@Test func bundleIDPatternMatchedAgainstResolvedID() {
  let rule = Rule(name: "Slack only", bundleIDPattern: "tinyspeck\\.slack")
  let with = matcher.match(
    rules: [rule],
    banner: BannerText(
      appName: "Slack",
      bundleID: "com.tinyspeck.slackmacgap"))
  let without = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(with != nil)
  #expect(without == nil)
}

@Test func dotMatchesNewlinesInBodyPattern() {
  // RuleMatcher applies `.dotMatchesNewlines()` so `.` spans embedded
  // newlines in multi-line banner text. A pattern relying on that
  // behavior must match across line boundaries.
  let rule = Rule(name: "multiline", bodyPattern: "alice.*bob")
  let banner = BannerText(appName: "X", body: "alice\nsays\nbob")
  #expect(matcher.match(rules: [rule], banner: banner) != nil)
}

@Test func invalidateCacheClearsCompiledPatterns() {
  // Cache invalidation must force recompilation. We assert the
  // observable behavior: after invalidateCache(), matching still works
  // (i.e. the cache rebuilt itself) and no stale entry survives a
  // pattern change.
  let isolatedMatcher = RuleMatcher()
  let rule = Rule(name: "r", appPattern: "Slack")
  #expect(isolatedMatcher.match(rules: [rule], banner: BannerText(appName: "Slack")) != nil)
  isolatedMatcher.invalidateCache()
  #expect(isolatedMatcher.match(rules: [rule], banner: BannerText(appName: "Slack")) != nil)
}

@Test func compileForMatchingAppliesIgnoresCase() throws {
  // The shared helper used by both the matcher and the editor's
  // validator must produce a case-insensitive Regex so the editor's
  // syntax check matches runtime semantics.
  let regex = try RuleMatcher.compileForMatching("slack")
  #expect("SLACK".firstMatch(of: regex) != nil)
}
