import AppKit
import ServiceManagement

/// BannerShift's view of its login-item registration, mapped from
/// `SMAppService.Status`.
///
/// `requiresApproval` means macOS registered the item but the user must
/// approve it in System Settings before it takes effect; `error` is a
/// transient or persistent Service Management failure (see
/// `LaunchAtLoginToggle.toggle`).
enum LaunchAtLoginState {
  case notRegistered
  case enabled
  case requiresApproval
  case error
}

/// Reads and flips whether BannerShift launches at login, via
/// `SMAppService.mainApp`.
///
/// The single place that touches Service Management; `MenuBarController`
/// drives it from the menu and surfaces `requiresApproval` to the user.
enum LaunchAtLoginToggle {
  /// Current registration state, derived from `SMAppService.mainApp.status`.
  ///
  /// `.notFound` is folded into `.notRegistered` (same meaning to the
  /// user); an unknown future status becomes `.error`.
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
