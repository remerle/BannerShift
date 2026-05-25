import Foundation
import Testing

@testable import BannerShiftCore

@Test func bannerTextEmptyDefaults() {
  let banner = BannerText()
  #expect(banner.appName.isEmpty)
  #expect(banner.title.isEmpty)
  #expect(banner.body.isEmpty)
  #expect(banner.bundleID == nil)
}

@Test func bannerTextEquatable() {
  let left = BannerText(appName: "A", title: "T")
  let right = BannerText(appName: "A", title: "T")
  #expect(left == right)
}

@Test func ruleInitDefaults() {
  let rule = Rule()
  #expect(!rule.id.isEmpty)
  #expect(rule.enabled == true)
  #expect(rule.position == nil)
  #expect(rule.animation == nil)
  #expect(rule.appPattern == nil)
}

@Test func ruleCodableRoundTrip() throws {
  let rule = Rule(
    id: "1234",
    name: "Slack DMs",
    enabled: true,
    appPattern: "Slack",
    titlePattern: "^DM",
    position: .middle,
    animation: .shake
  )
  let data = try JSONEncoder().encode(rule)
  let back = try JSONDecoder().decode(Rule.self, from: data)
  #expect(back == rule)
}

@Test func ruleCodableHandlesNilFields() throws {
  let rule = Rule(name: "Catchall")
  let data = try JSONEncoder().encode(rule)
  let back = try JSONDecoder().decode(Rule.self, from: data)
  #expect(back == rule)
}

@Test func ruleDefaultsPinsToListFalse() {
  #expect(Rule().pinsToList == false)
}

@Test func ruleCodableRoundTripsPinsToList() throws {
  let rule = Rule(name: "Pin me", appPattern: "Slack", pinsToList: true)
  let data = try JSONEncoder().encode(rule)
  let back = try JSONDecoder().decode(Rule.self, from: data)
  #expect(back == rule)
  #expect(back.pinsToList == true)
}
