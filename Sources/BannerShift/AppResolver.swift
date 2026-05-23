import AppKit
import Foundation

enum AppResolver {
  static func bundleID(forAppName name: String) -> String? {
    guard !name.isEmpty else { return nil }
    let lower = name.lowercased()
    for app in NSWorkspace.shared.runningApplications {
      if let n = app.localizedName?.lowercased(), n == lower {
        return app.bundleIdentifier
      }
    }
    return nil
  }
}
