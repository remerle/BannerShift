import Foundation

public enum Constants {
  /// Bundle ID. Must match Info.plist (§18).
  public static let bundleIdentifier = "com.emerle.BannerShift"

  /// Bundle ID of the system process that owns notification UI windows.
  /// Macros 13–26 have used "com.apple.notificationcenterui". Fragile.
  public static let notificationUIBundleIdentifier = "com.apple.notificationcenterui"

  /// AX subroles that identify a banner-style element inside a window.
  /// Updated occasionally across major macOS releases (§20.1).
  public static let bannerSubroles: Set<String> = [
    "AXNotificationCenterBanner",
    "AXNotificationCenterAlert",
    "AXSystemDialog",
  ]

  /// AX identifier present only on a control inside an open Notification
  /// Center panel — used to distinguish panel from banner (§9, §20.2).
  public static let notificationCenterPanelIdentifier = "widget-editor"

  /// Padding (in points) to keep middle- and bottom-row positions clear of
  /// the Dock. Single source of truth (§7).
  public static let dockPadding: CGFloat = 30

  /// Debounce interval for coalescing event bursts (§10).
  public static let eventDebounceInterval: TimeInterval = 0.030

  /// Max file-log size in bytes; truncated at launch if exceeded.
  public static let maxLogFileSize: Int = 5 * 1024 * 1024
}
