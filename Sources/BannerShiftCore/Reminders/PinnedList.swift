import Foundation

/// One row in the pinned-notifications list: a collapsed group of banners
/// sharing a `(bundleID ?? lowercased appName, title)` key, with an
/// occurrence `count` and a stable `id` for the UI.
public struct PinnedItem: Equatable, Sendable, Identifiable {
  /// Stable identity derived from the collapse key; also used as the
  /// dismiss target.
  public let id: String

  /// Display name of the source app (newest wins on collapse).
  public let appName: String

  /// Resolved bundle identifier, or nil.
  ///
  /// Used to open the source app on a row click; nil means the row is not
  /// clickable to an app.
  public let bundleID: String?

  /// Title line shared by the collapsed group.
  public let title: String

  /// Latest body text seen for this group.
  public let body: String

  /// Number of distinct banner arrivals collapsed into this row.
  ///
  /// Rendered as a badge when greater than one.
  public var count: Int
}

/// In-memory, ordered list of pinned notifications with collapse-by-key semantics.
///
/// Pure value type — no AppKit, no persistence; the executable target holds one
/// as mutable state and re-renders the panel after each mutation.
///
/// Ordering is newest-group-first. `pin` collapses a repeat into the existing
/// group, bumps it to the top, and keeps the newest body. The list is capped at
/// `Constants.maxPinnedItems`, evicting the oldest group (at the bottom) when a
/// new group overflows it.
public struct PinnedList: Equatable {
  /// Current rows, newest group first.
  public private(set) var items: [PinnedItem] = []

  /// Creates an empty pinned list.
  public init() {}

  /// True when no items are pinned; drives whether the panel is shown.
  public var isEmpty: Bool { items.isEmpty }

  /// Capture one notification.
  ///
  /// If a group with the same collapse key exists, increments its count,
  /// adopts the newest body and app name, and moves it to the top.
  /// Otherwise inserts a new group at the top and evicts the oldest group if
  /// the cap is exceeded.
  public mutating func pin(_ notification: CapturedNotification) {
    let key = Self.collapseKey(
      bundleID: notification.bundleID, appName: notification.appName, title: notification.title)
    if let index = items.firstIndex(where: { $0.id == key }) {
      let existing = items.remove(at: index)
      let updated = PinnedItem(
        id: key, appName: notification.appName, bundleID: notification.bundleID,
        title: notification.title, body: notification.body, count: existing.count + 1)
      items.insert(updated, at: 0)
      return
    }
    items.insert(
      PinnedItem(
        id: key, appName: notification.appName, bundleID: notification.bundleID,
        title: notification.title, body: notification.body, count: 1),
      at: 0)
    if items.count > Constants.maxPinnedItems {
      items.removeLast()
    }
  }

  /// Remove the group with `id`, if present.
  ///
  /// No-op when no group matches.
  public mutating func dismiss(id: String) {
    items.removeAll { $0.id == id }
  }

  /// Remove every group.
  public mutating func dismissAll() {
    items.removeAll()
  }

  /// Collapse key: bundle ID when present (apps with the same display name
  /// stay distinct), otherwise the case-folded app name, joined to the title
  /// with a NUL that cannot appear in either field.
  private static func collapseKey(bundleID: String?, appName: String, title: String) -> String {
    let appPart = bundleID ?? appName.lowercased()
    return appPart + "\u{0}" + title
  }
}
