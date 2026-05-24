import AppKit

extension NSApplication {
  /// Bring the app to the front using the API appropriate to the
  /// current macOS version.
  ///
  /// `activate(ignoringOtherApps:)` is deprecated on macOS 14+ in favor
  /// of the argumentless `activate()`. The deployment target is macOS
  /// 13, so the deprecated form is the correct call on 13 and the new
  /// form is the correct call on 14+. This helper isolates the
  /// `#available` gate to one place.
  ///
  /// Called from the rule editor and About window when they are shown
  /// or re-shown so the LSUIElement background agent's windows come to
  /// the front rather than appearing behind other apps.
  func bringToFront() {
    if #available(macOS 14.0, *) {
      activate()
    } else {
      activate(ignoringOtherApps: true)
    }
  }
}
