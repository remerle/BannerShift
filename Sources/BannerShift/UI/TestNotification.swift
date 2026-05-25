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

  private static func post(positionName: String) {
    let content = UNMutableNotificationContent()
    content.title = "BannerShift"
    content.subtitle = positionName
    content.body = "If you can see this in the chosen position, it's working."
    let center = UNUserNotificationCenter.current()
    // Two macOS behaviours conspire to make repeated test sends "only work the
    // first time" unless we both vary the id and clear prior deliveries:
    //   1. Re-posting the *same* identifier updates the existing Notification
    //      Center entry in place without re-alerting — no new banner.
    //   2. A new notification posted while a previous one from the same app is
    //      still sitting in Notification Center can be coalesced into that group
    //      and delivered silently instead of as a banner.
    // So: clear any prior test delivery first, then post a fresh unique id.
    // BannerShift posts *only* this test notification, so clearing all of our
    // delivered notifications is exactly "remove my earlier test banners."
    center.removeAllDeliveredNotifications()
    let identifier = "\(Constants.bundleIdentifier).test.\(UUID().uuidString)"
    let req = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

    // A banner only draws while BannerShift is a *background* app. When it is
    // the active app (e.g. the rules editor is frontmost), macOS routes the
    // notification to `willPresent`, and for an LSUIElement agent the forced
    // `.banner` there does not render — the test would silently do nothing.
    // Resign active first, then post once the app has actually given it up
    // (deactivation lands on a later run-loop turn). When already in the
    // background, post immediately so the banner isn't needlessly delayed.
    if NSApp.isActive {
      NSApp.deactivate()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { center.add(req) }
    } else {
      center.add(req)
    }
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

/// Requests banner presentation for BannerShift's own notifications.
///
/// macOS suppresses a notification's banner when its app is active, routing it
/// to Notification Center instead and calling this delegate to ask how to
/// present. The primary fix for "Send a Test Notification" is to post while the
/// app is backgrounded (see `TestNotification.post`), where the banner draws
/// normally; for an `LSUIElement` agent the forced `.banner` here does not
/// reliably render while active. This delegate is the belt-and-suspenders:
/// should a delivery ever arrive while foreground, it still asks for the
/// banner rather than letting macOS drop it silently. BannerShift posts only
/// the test notification, so presenting every delivery is correct here.
///
/// Set as `UNUserNotificationCenter.current().delegate` during launch and
/// retained by `AppDelegate`.
final class TestNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }
}
