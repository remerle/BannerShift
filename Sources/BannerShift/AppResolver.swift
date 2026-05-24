import AppKit
import Foundation

/// Maps a banner's source-app display name (e.g. `"Slack"`) to its
/// bundle identifier (e.g. `"com.tinyspeck.slackmacgap"`).
///
/// Backed by an event-driven cache so the lookup does not enumerate
/// `NSWorkspace.shared.runningApplications` on every banner reposition.
/// `BannerMover.processWindow` calls this once per visible window per
/// debounce pass on the main thread, which made the prior linear scan
/// (100-300 entries on a typical desktop) a measurable cost in the
/// reposition hot path.
///
/// All access is on the main thread, matching the threading model of
/// `NSWorkspace` notifications and the AX event pipeline. The cache is
/// not Sendable and must not be touched from other queues.
enum AppResolver {
  /// Lowercased `localizedName` -> `bundleIdentifier`.
  ///
  /// Lazily seeded from a single enumeration on first lookup; thereafter
  /// maintained incrementally via NSWorkspace launch/terminate
  /// notifications.
  private static var cache: [String: String] = [:]
  private static var observersInstalled = false

  /// Returns the bundle identifier for the running application whose
  /// `localizedName` case-insensitively equals `name`, or nil if no
  /// running application matches.
  static func bundleID(forAppName name: String) -> String? {
    guard !name.isEmpty else { return nil }
    ensureCacheSeeded()
    return cache[name.lowercased()]
  }

  private static func ensureCacheSeeded() {
    guard !observersInstalled else { return }
    observersInstalled = true
    for app in NSWorkspace.shared.runningApplications {
      insert(app)
    }
    let nc = NSWorkspace.shared.notificationCenter
    nc.addObserver(
      forName: NSWorkspace.didLaunchApplicationNotification,
      object: nil, queue: .main
    ) { note in
      guard
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else { return }
      insert(app)
    }
    nc.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification,
      object: nil, queue: .main
    ) { note in
      guard
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
          as? NSRunningApplication
      else { return }
      remove(app)
    }
  }

  private static func insert(_ app: NSRunningApplication) {
    guard let name = app.localizedName?.lowercased(),
      let bundleID = app.bundleIdentifier
    else { return }
    cache[name] = bundleID
  }

  private static func remove(_ app: NSRunningApplication) {
    guard let name = app.localizedName?.lowercased() else { return }
    // Only drop the entry if the bundle ID matches; another app with the
    // same display name may still be running (rare but possible with
    // helper processes).
    if let existing = cache[name], existing == app.bundleIdentifier {
      cache.removeValue(forKey: name)
    }
  }
}
