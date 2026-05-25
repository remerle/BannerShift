import Testing

@testable import BannerShiftCore

@Test func pinInsertsNewRow() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "Q", body: "hi"))
  #expect(list.items.count == 1)
  #expect(list.items[0].appName == "Slack")
  #expect(list.items[0].title == "Q")
  #expect(list.items[0].body == "hi")
  #expect(list.items[0].count == 1)
}

@Test func pinCollapsesSameAppAndTitle() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "Q", body: "one"))
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "Q", body: "two"))
  #expect(list.items.count == 1)
  #expect(list.items[0].count == 2)
  #expect(list.items[0].body == "two")  // newest body wins
}

@Test func pinKeepsDistinctTitlesSeparate() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Slack", title: "R"))
  #expect(list.items.count == 2)
}

@Test func pinNewestGroupOnTop() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  #expect(list.items[0].appName == "Mail")  // newest first
  #expect(list.items[1].appName == "Slack")
}

@Test func rePinBumpsGroupToTop() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))  // re-pin oldest
  #expect(list.items[0].appName == "Slack")
  #expect(list.items[0].count == 2)
  #expect(list.items.count == 2)
}

@Test func collapseKeyFallsBackToAppNameCaseInsensitively() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: nil, title: "Q"))
  list.pin(CapturedNotification(appName: "slack", bundleID: nil, title: "Q"))
  #expect(list.items.count == 1)
  #expect(list.items[0].count == 2)
}

@Test func bundleIDDistinguishesSameAppNameAndTitle() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "App", bundleID: "com.a", title: "Q"))
  list.pin(CapturedNotification(appName: "App", bundleID: "com.b", title: "Q"))
  #expect(list.items.count == 2)
}

@Test func dismissRemovesOneRow() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  let id = list.items[0].id
  list.dismiss(id: id)
  #expect(list.items.count == 1)
  #expect(list.items.allSatisfy { $0.id != id })
}

@Test func dismissAllEmpties() {
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", title: "Q"))
  list.pin(CapturedNotification(appName: "Mail", title: "R"))
  list.dismissAll()
  #expect(list.isEmpty)
}

@Test func capEvictsOldestGroup() {
  var list = PinnedList()
  for idx in 0..<(Constants.maxPinnedItems + 5) {
    list.pin(CapturedNotification(appName: "App\(idx)", title: "T\(idx)"))
  }
  #expect(list.items.count == Constants.maxPinnedItems)
  // The 5 oldest (App0..App4) were evicted from the bottom; newest is on top.
  #expect(list.items.first?.appName == "App\(Constants.maxPinnedItems + 4)")
  #expect(list.items.contains { $0.appName == "App0" } == false)
  // App5 is the oldest survivor: eviction must not overshoot past the cap.
  #expect(list.items.contains { $0.appName == "App5" })
}

@Test func titleIsCaseSensitiveInCollapseKey() {
  // Unlike the app-name fallback, the title is matched verbatim by design:
  // titles differing only in case stay distinct groups.
  var list = PinnedList()
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "New message"))
  list.pin(CapturedNotification(appName: "Slack", bundleID: "com.slack", title: "New Message"))
  #expect(list.items.count == 2)
}
