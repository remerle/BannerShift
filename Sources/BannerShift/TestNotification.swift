import AppKit
import BannerShiftCore
import UserNotifications

enum TestNotification {
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
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
