import Testing

@testable import BannerShiftCore

@Test func starBecomesDotStar() {
  #expect(WildcardPattern.regexPattern(from: "*") == ".*")
  #expect(WildcardPattern.regexPattern(from: "Slack*") == "Slack.*")
  #expect(WildcardPattern.regexPattern(from: "*meeting*") == ".*meeting.*")
}

@Test func metacharactersAreEscapedToLiterals() {
  // A bundle id's dots must match literally, not as regex "any character".
  #expect(WildcardPattern.regexPattern(from: "com.apple.mail") == "com\\.apple\\.mail")
  // Brackets, anchors, and quantifiers are literal text under wildcards.
  #expect(WildcardPattern.regexPattern(from: "[x]") == "\\[x\\]")
  #expect(WildcardPattern.regexPattern(from: "^DM") == "\\^DM")
}

@Test func emptyWildcardProducesEmptyPattern() {
  #expect(WildcardPattern.regexPattern(from: "").isEmpty)
}
