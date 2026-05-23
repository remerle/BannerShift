import Foundation

/// Extracted text content of a banner, in the shape `RuleMatcher`
/// expects.
///
/// Read from the AX subtree by the executable target and passed into
/// the matcher as an opaque value. Treat the contents as sensitive: it
/// is the full visible text of the user's notification and must never
/// be logged outside of explicit debug mode.
public struct BannerText: Equatable, Sendable {
  /// Localized display name of the source application (e.g. `"Slack"`).
  ///
  /// Populated from the banner's leading text element.
  public let appName: String

  /// Resolved bundle identifier (e.g. `"com.tinyspeck.slackmacgap"`)
  /// when available, otherwise nil.
  ///
  /// Populated by the executable target when it can map `appName` back
  /// to a bundle via Launch Services. Nil means no mapping was found;
  /// rules with `bundleIDPattern` set will not match such banners.
  public let bundleID: String?

  /// Banner title line as rendered on screen.
  ///
  /// Empty if the banner had no distinct title row.
  public let title: String

  /// Banner subtitle line.
  ///
  /// Empty if the banner had no subtitle row.
  public let subtitle: String

  /// Banner body text.
  ///
  /// Empty if the banner had no body row.
  public let body: String

  /// Constructs a banner-text snapshot.
  ///
  /// All fields default to empty so tests can build minimal fixtures
  /// without specifying every argument.
  public init(
    appName: String = "",
    bundleID: String? = nil,
    title: String = "",
    subtitle: String = "",
    body: String = ""
  ) {
    self.appName = appName
    self.bundleID = bundleID
    self.title = title
    self.subtitle = subtitle
    self.body = body
  }
}
