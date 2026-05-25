/// An immutable snapshot of one captured banner, handed to `PinnedList`.
///
/// Carries the same notification text the matcher sees, so treat it as
/// sensitive: it must never be logged outside explicit debug mode and is
/// held only in memory (never written to disk). `bundleID` is the value
/// already resolved during rule matching, reused so a row click can open the
/// source app without re-resolving.
///
/// `BannerText` carries a `subtitle` field, but `CapturedNotification`
/// intentionally omits it: the pinned panel shows the app name, title, and
/// body only. This is not an oversight; subtitles in macOS notifications are
/// used inconsistently and rarely carry information that the title or body
/// does not already convey.
public struct CapturedNotification: Equatable, Sendable {
  /// Localized display name of the source app (e.g. `"Slack"`).
  public let appName: String

  /// Resolved bundle identifier, or nil when no mapping was found.
  ///
  /// A nil value means a row click cannot open the source app.
  public let bundleID: String?

  /// Banner title line; part of the collapse key.
  public let title: String

  /// Banner body text; the newest body wins when a group collapses.
  public let body: String

  /// All fields default to empty so tests can build minimal fixtures.
  public init(
    appName: String = "", bundleID: String? = nil, title: String = "", body: String = ""
  ) {
    self.appName = appName
    self.bundleID = bundleID
    self.title = title
    self.body = body
  }
}
