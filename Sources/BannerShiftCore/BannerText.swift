import Foundation

public struct BannerText: Equatable, Sendable {
  public let appName: String
  public let bundleID: String?
  public let title: String
  public let subtitle: String
  public let body: String

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
