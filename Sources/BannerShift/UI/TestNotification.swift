import AppKit
import BannerShiftCore
import UserNotifications

/// Posts a real local notification so the user can confirm banners land
/// in the chosen position.
///
/// Backed by `UNUserNotificationCenter`, so it requests authorization on
/// first use and, if notifications are disabled, offers to open the
/// Notifications pane in System Settings. Invoked from the menu bar's
/// "Send a Test Notification".
enum TestNotification {
  /// Send a test banner labeled with `positionName`, requesting
  /// notification permission first if undetermined and alerting the user
  /// if it has been denied.
  static func send(positionName: String) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .notDetermined:
          center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
              if granted { post(positionName: positionName) } else { showDeniedAlert() }
            }
          }

        case .authorized, .provisional, .ephemeral:
          post(positionName: positionName)

        case .denied:
          showDeniedAlert()

        @unknown default:
          showDeniedAlert()
        }
      }
    }
  }

  // Stable identifier so repeated "Send a Test Notification" invocations
  // replace the prior delivery in Notification Center rather than
  // accumulating distinct entries the user has to dismiss one by one.
  private static let identifier = "\(Constants.bundleIdentifier).test"

  private static func post(positionName: String) {
    let content = UNMutableNotificationContent()
    content.title = "BannerShift"
    content.subtitle = positionName
    content.body = "If you can see this in the chosen position, it's working."
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    center.add(req, withCompletionHandler: nil)
  }

  private static func showDeniedAlert() {
    let alert = NSAlert()
    alert.messageText = "Notifications are disabled for BannerShift"
    alert.informativeText =
      "Enable notifications in System Settings → Notifications → BannerShift "
      + "to send a test banner."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      openNotificationSettings()
    }
  }

  /// Open System Settings to the Notifications pane.
  ///
  /// macOS exposes no deep link to a specific app's notification row, so
  /// this lands the user on the Notifications list where BannerShift can be
  /// found. The `x-apple.systempreferences:` scheme is the documented way to
  /// open a System Settings pane by its extension bundle identifier.
  private static func openNotificationSettings() {
    guard
      let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
