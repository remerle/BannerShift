import CoreGraphics
import Foundation

/// Typed accessor for the small set of values BannerShift persists in
/// `UserDefaults`.
///
/// Reference-typed so the same instance can be shared by `AppDelegate`,
/// `MenuBarController`, and `BannerMover` without duplicating the
/// `UserDefaults` reference. All getters read live from defaults on
/// every access (no in-process cache) so a `defaults write` from the
/// command line takes effect without a relaunch.
public final class Preferences {
  /// `UserDefaults` key for the persisted default `Position`.
  public static let positionKey = "selectedPosition"

  /// `UserDefaults` key for whether the menu bar icon is hidden.
  public static let iconHiddenKey = "iconHidden"

  /// `UserDefaults` key for the debug-logging toggle.
  public static let debugLoggingKey = "debugLoggingEnabled"

  /// `UserDefaults` key for the pinned-list panel's saved frame origin.
  public static let pinnedPanelOriginKey = "pinnedPanelOrigin"

  private let defaults: UserDefaults

  /// Injectable initializer; production uses `.standard` and tests pass
  /// an isolated suite so they never read or mutate the real defaults.
  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Current default position used for banners that no rule overrides.
  ///
  /// Falls back to `.topMiddle` when the stored value is missing or
  /// not a recognized raw value.
  public var position: Position {
    get {
      guard let raw = defaults.string(forKey: Self.positionKey),
        let position = Position(rawValue: raw)
      else {
        return .topMiddle
      }
      return position
    }
    set { defaults.set(newValue.rawValue, forKey: Self.positionKey) }
  }

  /// Whether the menu bar icon should stay hidden across launches.
  ///
  /// Reset to `false` when the user re-activates the app (front-launch
  /// reveals the icon as a recovery affordance).
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

  /// Saved origin of the pinned-list panel, or nil if the user has never moved it.
  ///
  /// Stored as `"x,y"`. Only the window position is persisted;
  /// no notification content is ever written to defaults.
  public var pinnedPanelOrigin: CGPoint? {
    get {
      guard let raw = defaults.string(forKey: Self.pinnedPanelOriginKey) else { return nil }
      let parts = raw.split(separator: ",")
      guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
        return nil
      }
      return CGPoint(x: x, y: y)
    }
    set {
      guard let newValue else {
        defaults.removeObject(forKey: Self.pinnedPanelOriginKey)
        return
      }
      defaults.set("\(newValue.x),\(newValue.y)", forKey: Self.pinnedPanelOriginKey)
    }
  }
}
