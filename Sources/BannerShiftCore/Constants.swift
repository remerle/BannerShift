import Foundation

public enum Constants {
  /// Bundle identifier. Must match the `CFBundleIdentifier` value in `Info.plist`;
  /// the logger subsystem and rule-store UserDefaults suite both key off it.
  public static let bundleIdentifier = "com.emerle.BannerShift"

  /// Bundle ID of the system process that owns notification UI windows.
  /// Stable across macOS 13–26 but undocumented; expect Apple to rename or
  /// resplit this process across major OS releases.
  public static let notificationUIBundleIdentifier = "com.apple.notificationcenterui"

  /// AX subroles that identify a banner-style element inside a notification
  /// UI window. These names are not part of Apple's documented public API;
  /// expect them to change across major macOS releases. When any banner
  /// stops being repositioned after an OS upgrade, this is the first place
  /// to look.
  public static let bannerSubroles: Set<String> = [
    "AXNotificationCenterBanner",
    "AXNotificationCenterAlert",
    "AXSystemDialog",
  ]

  /// AX identifier present only on a control inside an open Notification
  /// Center panel. Used to distinguish an expanded Notification Center from
  /// a transient banner so the mover refuses to relocate the panel.
  public static let notificationCenterPanelIdentifier = "widget-editor"

  /// Padding (in points) to keep middle- and bottom-row banner positions
  /// clear of the Dock. Single source of truth for vertical-position math
  /// in `PositionCalculator`.
  public static let dockPadding: CGFloat = 30

  /// Debounce interval (seconds) for coalescing bursts of AX notifications.
  /// Tuned to drop redundant work without delaying the move long enough for
  /// the OS-default banner position to become visible.
  public static let eventDebounceInterval: TimeInterval = 0.030

  /// Max file-log size in bytes. `FileLogger` truncates the log at launch
  /// if the on-disk size exceeds this. Sized so that a few weeks of
  /// debug-logging activity fits comfortably.
  public static let maxLogFileSize: Int = 5 * 1024 * 1024
}
