import Foundation
import Testing

@testable import BannerShiftCore

@Test func bannerTextEmptyDefaults() {
  let t = BannerText()
  #expect(t.appName == "")
  #expect(t.title == "")
  #expect(t.body == "")
  #expect(t.bundleID == nil)
}

@Test func bannerTextEquatable() {
  let a = BannerText(appName: "A", title: "T")
  let b = BannerText(appName: "A", title: "T")
  #expect(a == b)
}

@Test func ruleInitDefaults() {
  let r = Rule()
  #expect(!r.id.isEmpty)
  #expect(r.enabled == true)
  #expect(r.position == nil)
  #expect(r.animation == nil)
  #expect(r.appPattern == nil)
}

@Test func ruleCodableRoundTrip() throws {
  let r = Rule(
    id: "1234",
    name: "Slack DMs",
    enabled: true,
    appPattern: "Slack",
    titlePattern: "^DM",
    position: .middle,
    animation: .shake
  )
  let data = try JSONEncoder().encode(r)
  let back = try JSONDecoder().decode(Rule.self, from: data)
  #expect(back == r)
}

@Test func ruleCodableHandlesNilFields() throws {
  let r = Rule(name: "Catchall")
  let data = try JSONEncoder().encode(r)
  let back = try JSONDecoder().decode(Rule.self, from: data)
  #expect(back == r)
}
