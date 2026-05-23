import Testing

@testable import BannerShiftCore

private let matcher = RuleMatcher()

@Test func emptyRulesReturnNil() {
  #expect(matcher.match(rules: [], banner: BannerText(appName: "X")) == nil)
}

@Test func ruleWithNoPatternsIsCatchall() {
  let catchall = Rule(name: "Catchall")
  let m = matcher.match(rules: [catchall], banner: BannerText(appName: "Whatever"))
  #expect(m?.rule.id == catchall.id)
}

@Test func appPatternMatchesCaseInsensitively() {
  let rule = Rule(name: "Slack rule", appPattern: "slack")
  let m = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
  #expect(m?.rule.id == rule.id)
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
  let a = Rule(name: "A", appPattern: "Slack", position: .middle)
  let b = Rule(name: "B", appPattern: "Slack", position: .topRight)
  let m = matcher.match(rules: [a, b], banner: BannerText(appName: "Slack"))
  #expect(m?.rule.id == a.id)
}

@Test func disabledRuleSkipped() {
  let disabled = Rule(name: "Off", enabled: false, appPattern: "Slack", position: .topLeft)
  let live = Rule(name: "On", appPattern: "Slack", position: .middle)
  let m = matcher.match(rules: [disabled, live], banner: BannerText(appName: "Slack"))
  #expect(m?.rule.id == live.id)
}

@Test func malformedRegexDoesNotMatch() {
  let bad = Rule(name: "Bad", appPattern: "[unterminated")
  #expect(matcher.match(rules: [bad], banner: BannerText(appName: "anything")) == nil)
}

@Test func malformedRegexInvokesDiagnosticLogger() {
  // plan §22: a malformed pattern must never be silently swallowed. The
  // matcher emits a diagnostic and treats the containing rule as disabled.
  var diagnostics: [String] = []
  let m = RuleMatcher(diagnosticLogger: { diagnostics.append($0) })
  let bad = Rule(name: "BrokenRule", appPattern: "[unterminated")
  let result = m.match(rules: [bad], banner: BannerText(appName: "Slack"))
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
