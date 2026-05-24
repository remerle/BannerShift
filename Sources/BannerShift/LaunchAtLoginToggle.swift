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

  /// Toggle the registration and return the live status after the call.
  ///
  /// The status is observed twice — once at the switch decision and
  /// once for the return — so an external change to `SMAppService`
  /// state between calls can produce a return value that does not
  /// match the action performed. Callers (e.g. `MenuBarController`)
  /// only use the return to decide whether to show the
  /// "Requires Approval" alert and tolerate this race in practice.
  ///
  /// `.error` from a `current` read is treated as `.notRegistered` and
  /// retried via `register()`. That keeps the most common transient
  /// failure (a momentarily-busy `smd`) self-healing without an extra
  /// UI surface; a persistent error still propagates because the
  /// retried `register()` returns the same `.error` from the second
  /// `current` read.
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
