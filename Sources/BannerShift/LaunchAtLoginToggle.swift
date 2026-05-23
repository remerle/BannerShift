import AppKit
import ServiceManagement

enum LaunchAtLoginState {
  case notRegistered
  case enabled
  case requiresApproval
  case error
}

enum LaunchAtLoginToggle {
  static var current: LaunchAtLoginState {
    switch SMAppService.mainApp.status {
    case .notRegistered: return .notRegistered
    case .enabled: return .enabled
    case .requiresApproval: return .requiresApproval
    case .notFound: return .notRegistered
    @unknown default: return .error
    }
  }

  /// Returns the new state after toggling.
  @discardableResult
  static func toggle() -> LaunchAtLoginState {
    do {
      switch current {
      case .enabled, .requiresApproval:
        try SMAppService.mainApp.unregister()

      case .notRegistered, .error:
        try SMAppService.mainApp.register()
      }
    } catch {
      return .error
    }
    return current
  }

  /// Opens the Login Items pane for the user if registration ended up in
  /// `requiresApproval`.
  static func openSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
