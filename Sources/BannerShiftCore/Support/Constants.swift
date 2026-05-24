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
  ///
  /// Verified: macOS 13 (Ventura) through macOS 26 (May 2026).
  public static let notificationUIBundleIdentifier = "com.apple.notificationcenterui"

  /// AX subroles that identify a banner-style element inside a
  /// notification UI window.
  ///
  /// These names are not part of Apple's documented public API; expect
  /// them to change across major macOS releases. When any banner stops
  /// being repositioned after an OS upgrade, this is the first place to
  /// look.
  ///
  /// Verified: macOS 13 (Ventura) through macOS 26 (May 2026).
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
  ///
  /// Verified: macOS 13 (Ventura) through macOS 26 (May 2026).
  public static let notificationCenterPanelIdentifier = "widget-editor"

  /// Padding (in points) to keep middle- and bottom-row banner
  /// positions clear of the Dock.
  ///
  /// Single source of truth for vertical-position math in
  /// `PositionCalculator`; the calculator centers banners on the
  /// visible area biased up by half this value so the Dock's presence
  /// does not visually push the banner off-center.
  ///
  /// The 30pt value was chosen as a conservative clearance above the
  /// auto-hidden Dock's reveal strip (about 4pt) and roughly half the
  /// default Dock icon size (~60pt with magnification). Tuning higher
  /// pushes the banner further off-center; tuning lower risks the
  /// banner being partially obscured when the Dock is visible.
  public static let dockPadding: CGFloat = 30

  /// Debounce interval (seconds) for coalescing bursts of AX
  /// notifications.
  ///
  /// Tuned to drop redundant work without delaying the move long enough
  /// for the OS-default banner position to become visible to the user.
  ///
  /// Lower values (≤10ms) defeat coalescing under burst conditions and
  /// raise main-thread CPU during banner spam; higher values (≥80ms)
  /// let the OS-default banner position render briefly before the move,
  /// producing a visible flicker. 30ms sits comfortably between both
  /// failure modes on the displays we have measured.
  public static let eventDebounceInterval: TimeInterval = 0.030

  /// Maximum file-log size in bytes before `FileLogger` truncates the
  /// log at launch.
  ///
  /// Sized so that a few weeks of debug-logging activity fits
  /// comfortably without unbounded growth on a long-lived install.
  public static let maxLogFileSize: Int = 5 * 1024 * 1024

  /// `AXError` raw value returned when `AXObserverAddNotification` is
  /// called for an element/notification pair that is already registered.
  ///
  /// Benign; the caller should silently ignore it. The Swift overlay's
  /// `AXError` enum does not expose a named case for this value, so
  /// callers compare against the raw `Int32`.
  public static let axErrorNotificationAlreadyRegistered: Int32 = -25200

  /// Maximum depth for recursive AX subtree traversal.
  ///
  /// AX data comes from an external OS process (`notificationcenterui`)
  /// and is treated as untrusted under the zero-trust-at-boundaries
  /// principle. A pathologically deep AX tree could otherwise exhaust
  /// the main-thread stack. Real notification UI trees are 2-4 levels
  /// deep on every macOS version we have observed; 32 is well above
  /// that ceiling and well below any stack pressure.
  public static let maxAXRecursionDepth: Int = 32

  /// Maximum length of any banner text field passed to `RuleMatcher`.
  ///
  /// Caps the input subject to a pattern match so a runaway-length
  /// body field cannot turn a backtracking-heavy regex into a
  /// main-thread stall. Real banner body text on macOS is well under
  /// this size; the limit is purely a defense against pathological
  /// inputs (rendering bug, malformed AX text, or an adversarially
  /// constructed notification).
  public static let maxBannerMatchSubjectLength: Int = 4096
}
