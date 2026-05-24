import ApplicationServices
import Foundation

/// Gate for the Accessibility permission that BannerShift cannot operate
/// without.
///
/// A namespace around the one trust check the app makes at launch; see
/// `isTrustedOrPrompt()` for the prompt side effect and the fail-fast
/// contract callers must honor.
enum AccessibilityPermission {
  /// Returns true iff the process is trusted to use the Accessibility API.
  ///
  /// Side effect: if not trusted, the system will display the standard
  /// prompt directing the user to System Settings → Privacy & Security →
  /// Accessibility. The prompt is a side effect of the underlying
  /// `AXIsProcessTrustedWithOptions` call with `kAXTrustedCheckOptionPrompt`.
  ///
  /// This method does **not** terminate the process on a `false` return.
  /// Per the fail-fast policy of this app, callers must terminate themselves
  /// when this returns `false`. BannerShift refuses to run in a degraded mode
  /// without Accessibility access. See
  /// `AppDelegate.applicationDidFinishLaunching` for the canonical handling.
  static func isTrustedOrPrompt() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
    let options: CFDictionary = [key: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
