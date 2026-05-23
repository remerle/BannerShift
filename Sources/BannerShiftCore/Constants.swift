import Foundation

/// Single source of truth for OS-dependent magic strings, magic
/// numbers, and tunable constants used by the reposition pipeline.
///
/// Anything that ties us to an undocumented macOS internal lives here
/// so that when an OS upgrade breaks BannerShift, the maintainer has
/// exactly one file to look at first.
public enum Constants {
  /// Bundle identifier of this app.
  ///
  /// Must match the `CFBundleIdentifier` value in `Info.plist`; the
  /// logger subsystem and rule-store `UserDefaults` suite both key off
  /// it.
  public static let bundleIdentifier = "com.emerle.BannerShift"

  /// Bundle ID of the system process that owns notification UI windows.
  ///
  /// Stable across recent macOS versions but undocumented; expect Apple
  /// to rename or resplit this process across major OS releases.
  public static let notificationUIBundleIdentifier = "com.apple.notificationcenterui"

  /// AX subroles that identify a banner-style element inside a
  /// notification UI window.
  ///
  /// These names are not part of Apple's documented public API; expect
  /// them to change across major macOS releases. When any banner stops
  /// being repositioned after an OS upgrade, this is the first place to
  /// look.
  public static let bannerSubroles: Set<String> = [
    "AXNotificationCenterBanner",
    "AXNotificationCenterAlert",
    "AXSystemDialog",
  ]

  /// AX identifier present only on a control inside an open Notification
  /// Center panel.
  ///
  /// Used to distinguish an expanded Notification Center from a
  /// transient banner so the mover refuses to relocate the panel.
  public static let notificationCenterPanelIdentifier = "widget-editor"

  /// Padding (in points) to keep middle- and bottom-row banner
  /// positions clear of the Dock.
  ///
  /// Single source of truth for vertical-position math in
  /// `PositionCalculator`; the calculator centers banners on the
  /// visible area biased up by half this value so the Dock's presence
  /// does not visually push the banner off-center.
  public static let dockPadding: CGFloat = 30

  /// Debounce interval (seconds) for coalescing bursts of AX
  /// notifications.
  ///
  /// Tuned to drop redundant work without delaying the move long enough
  /// for the OS-default banner position to become visible to the user.
  public static let eventDebounceInterval: TimeInterval = 0.030

  /// Maximum file-log size in bytes before `FileLogger` truncates the
  /// log at launch.
  ///
  /// Sized so that a few weeks of debug-logging activity fits
  /// comfortably without unbounded growth on a long-lived install.
  public static let maxLogFileSize: Int = 5 * 1024 * 1024
}
