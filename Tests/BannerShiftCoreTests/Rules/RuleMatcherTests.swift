import Testing

@testable import BannerShiftCore

private let matcher = RuleMatcher()

@Test func emptyRulesReturnNil() {
  #expect(matcher.match(rules: [], banner: BannerText(appName: "X")) == nil)
}

@Test func ruleWithNoPatternsMatchesNothing() {
  // A rule with no criteria is a no-op, not a catch-all.
  let empty = Rule(name: "Empty")
  #expect(matcher.match(rules: [empty], banner: BannerText(appName: "Whatever")) == nil)
}

@Test func appPatternMatchesCaseInsensitively() {
  let rule = Rule(name: "Slack rule", appPattern: "slack")
  let match = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(match?.rule.id == rule.id)
}

@Test func allSetPatternsMustMatch() {
  // Wildcard "DM*" matches a title that starts with DM; AND'd with the app.
  let rule = Rule(name: "Slack DMs", appPattern: "Slack", titlePattern: "DM*")
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

@Test func bundleIDPatternMatchedAgainstResolvedID() {
  // Substring wildcard against the resolved bundle id.
  let rule = Rule(name: "Slack only", bundleIDPattern: "tinyspeck")
  let with = matcher.match(
    rules: [rule],
    banner: BannerText(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"))
  let without = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(with != nil)
  #expect(without == nil)
}

@Test func wildcardBundlePatternDoesNotMatchUnresolvedBundleID() {
  // Regression: a wildcard `bundleIDPattern` compiles to `.*`, which matches
  // the empty string. A banner whose bundle ID could not be resolved (nil)
  // must NOT match such a rule — nil is not coalesced to "". This upholds
  // BannerText.bundleID's documented contract.
  let rule = Rule(name: "Any bundle", bundleIDPattern: "*")
  let resolved = matcher.match(
    rules: [rule], banner: BannerText(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"))
  let unresolved = matcher.match(
    rules: [rule], banner: BannerText(appName: "Slack", bundleID: nil))
  #expect(resolved != nil, "a wildcard bundle pattern matches any resolved bundle ID")
  #expect(unresolved == nil, "a wildcard bundle pattern must not match a nil bundle ID")
}

@Test func wildcardBundlePatternMatchesEmptyResolvedBundleID() {
  // A present-but-empty bundle ID is a resolved (non-nil) value, so a
  // wildcard still matches it — only the nil (unresolved) case is excluded.
  let rule = Rule(name: "Any bundle", bundleIDPattern: "*")
  let match = matcher.match(
    rules: [rule], banner: BannerText(appName: "X", bundleID: ""))
  #expect(match != nil)
}

@Test func literalDotInBundlePatternIsNotWildcard() {
  // The dot in a bundle pattern matches a literal dot, not any character.
  let rule = Rule(name: "Mail", bundleIDPattern: "com.apple.mail")
  let hit = matcher.match(
    rules: [rule], banner: BannerText(appName: "Mail", bundleID: "com.apple.mail"))
  let miss = matcher.match(
    rules: [rule], banner: BannerText(appName: "Mail", bundleID: "comXappleXmail"))
  #expect(hit != nil)
  #expect(miss == nil)
}

@Test func starMatchesAcrossNewlinesInBody() {
  // `*` becomes `.*` and the matcher applies dotMatchesNewlines, so a star
  // spans embedded newlines in multi-line banner text.
  let rule = Rule(name: "multiline", bodyPattern: "alice*bob")
  let banner = BannerText(appName: "X", body: "alice\nsays\nbob")
  #expect(matcher.match(rules: [rule], banner: banner) != nil)
}

@Test func invalidateCacheClearsCompiledPatterns() {
  let isolatedMatcher = RuleMatcher()
  let rule = Rule(name: "r", appPattern: "Slack")
  #expect(isolatedMatcher.match(rules: [rule], banner: BannerText(appName: "Slack")) != nil)
  isolatedMatcher.invalidateCache()
  #expect(isolatedMatcher.match(rules: [rule], banner: BannerText(appName: "Slack")) != nil)
}

@Test func compileForMatchingAppliesIgnoresCase() throws {
  let regex = try RuleMatcher.compileForMatching("slack")
  #expect("SLACK".firstMatch(of: regex) != nil)
}
