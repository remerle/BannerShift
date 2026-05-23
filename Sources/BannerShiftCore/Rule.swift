import Foundation

public struct Rule: Equatable, Sendable, Codable, Identifiable {
  public let id: String
  public var name: String
  public var enabled: Bool
  public var appPattern: String?
  public var bundleIDPattern: String?
  public var titlePattern: String?
  public var subtitlePattern: String?
  public var bodyPattern: String?
  public var position: Position?
  public var animation: Animation?

  public init(
    id: String = UUID().uuidString,
    name: String = "",
    enabled: Bool = true,
    appPattern: String? = nil,
    bundleIDPattern: String? = nil,
    titlePattern: String? = nil,
    subtitlePattern: String? = nil,
    bodyPattern: String? = nil,
    position: Position? = nil,
    animation: Animation? = nil
  ) {
    self.id = id
    self.name = name
    self.enabled = enabled
    self.appPattern = appPattern
    self.bundleIDPattern = bundleIDPattern
    self.titlePattern = titlePattern
    self.subtitlePattern = subtitlePattern
    self.bodyPattern = bodyPattern
    self.position = position
    self.animation = animation
  }
}
