import ApplicationServices
import Foundation

enum AccessibilityPermission {
  /// Returns true iff the process is trusted to use the Accessibility API.
  ///
  /// Side effect: if not trusted, the system will display the standard
  /// prompt directing the user to System Settings → Privacy & Security →
  /// Accessibility. The prompt is a side effect of the underlying
  /// `AXIsProcessTrustedWithOptions` call with `kAXTrustedCheckOptionPrompt`.
  ///
  /// This method does **not** terminate the process on a `false` return.
  /// Per the fail-fast policy (plan §4), callers must terminate themselves
  /// when this returns `false`. See `AppDelegate.applicationDidFinishLaunching`
  /// for the canonical handling.
  static func isTrustedOrPrompt() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
    let options: CFDictionary = [key: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
