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
  /// Must contain only subroles carried by the *banner element itself*,
  /// never the subrole of its enclosing window: `AXBannerFinder` returns
  /// the first element matching one of these and the mover measures that
  /// element's frame. On macOS 26 the notification UI is a single
  /// full-screen window whose own subrole is `AXSystemDialog`, so that
  /// value identifies a container, not a banner, and is excluded.
  ///
  /// Verified: macOS 13 (Ventura) through macOS 26 (May 2026).
  public static let bannerSubroles: Set<String> = [
    "AXNotificationCenterBanner",
    "AXNotificationCenterAlert",
  ]

  /// AX identifier substring present only on a control inside an open
  /// Notification Center panel.
  ///
  /// Used to distinguish an expanded Notification Center from a transient
  /// banner so the mover refuses to relocate the panel. `NotificationCenter`
  /// `PanelDetector` matches this as a **substring**, not an exact value: the
  /// control is named `widget-editor` on macOS 13–15 and `widget-editor-button`
  /// on macOS 26, and substring matching covers both (and any future suffix
  /// change) from one constant.
  ///
  /// Verified: macOS 13 (Ventura) through macOS 26 (May 2026).
  public static let notificationCenterPanelIdentifier = "widget-editor"

  /// AX attribute name for the ordered-children relationship.
  ///
  /// Not a documented public AX constant (there is no `kAX…` symbol for it).
  /// The macOS 26 SwiftUI notification UI exposes some descendants only
  /// through this relationship, so a `kAXChildrenAttribute`-only tree walk
  /// can miss them; `NotificationCenterPanelDetector` walks both. If a future
  /// macOS release renames this attribute, panel detection silently breaks —
  /// this is the one place to update.
  ///
  /// Verified: present on macOS 26 (May 2026).
  public static let axOrderedChildrenAttribute = "AXOrderedChildren"

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

  /// Inset (in points) of a banner's right edge from the right edge of its
  /// container notification window when the banner is at rest.
  ///
  /// The banner always comes to rest in the same top-right spot inside the
  /// full-display container window. Anchoring to that fixed inset lets the
  /// mover compute the banner's resting frame from the window width and the
  /// banner's own width alone, so it can reposition the container the moment
  /// a banner appears rather than waiting for the slide-in animation to
  /// finish (the live frame's `minX` is off-screen mid-animation). Measured
  /// at 16pt on macOS 13 through macOS 26.
  public static let bannerRightPadding: CGFloat = 16

  /// Coalescing window (seconds) for bursts of AX notifications.
  ///
  /// `Debouncer` fires the reposition pass on the *leading* edge — the
  /// first event moves the container immediately, before the banner
  /// animates into view — so this interval no longer gates how fast the
  /// move happens. It only sizes the window over which follow-up events
  /// during a banner's slide-in are coalesced into a single trailing
  /// re-apply.
  ///
  /// Lower values (≤10ms) close the window before a banner finishes
  /// sliding in, so each event runs its own pass and main-thread CPU
  /// rises under banner spam; higher values (≥80ms) coalesce events from
  /// genuinely distinct banners into one trailing pass and can delay the
  /// re-apply for the second banner. 30ms covers a single slide-in
  /// without bleeding into the next banner on the displays we measured.
  public static let eventDebounceInterval: TimeInterval = 0.030

  /// Maximum file-log size in bytes before `FileLogger` truncates the
  /// log at launch.
  ///
  /// Sized so that a few weeks of debug-logging activity fits
  /// comfortably without unbounded growth on a long-lived install.
  public static let maxLogFileSize: Int = 5 * 1024 * 1024

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

  /// Maximum number of rows the pinned-notifications list retains.
  ///
  /// Bounds memory and panel height against a chatty app. When a new group
  /// would exceed this, the oldest group (at the bottom of the newest-first
  /// list) is evicted. 50 comfortably covers a realistic backlog of pinned
  /// reminders without the panel growing past a screen.
  public static let maxPinnedItems: Int = 50
}
