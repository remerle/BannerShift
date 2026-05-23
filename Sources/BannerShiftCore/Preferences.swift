import Foundation

public final class Preferences {
  public static let positionKey = "selectedPosition"
  public static let iconHiddenKey = "iconHidden"
  public static let debugLoggingKey = "debugLoggingEnabled"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public var position: Position {
    get {
      guard let raw = defaults.string(forKey: Self.positionKey),
        let p = Position(rawValue: raw)
      else {
        return .topMiddle
      }
      return p
    }
    set { defaults.set(newValue.rawValue, forKey: Self.positionKey) }
  }

  public var iconHidden: Bool {
    get { defaults.bool(forKey: Self.iconHiddenKey) }
    set { defaults.set(newValue, forKey: Self.iconHiddenKey) }
  }

  /// Read live on each access so flipping the flag via
  /// `defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES`
  /// takes effect without a relaunch. `FileLogger` re-evaluates this on
  /// every `debug(_:)` call for the same reason.
  public var debugLoggingEnabled: Bool {
    get { defaults.bool(forKey: Self.debugLoggingKey) }
    set { defaults.set(newValue, forKey: Self.debugLoggingKey) }
  }
}
