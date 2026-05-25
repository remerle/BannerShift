import Foundation

/// One user-defined rule: a conjunction of wildcard patterns over banner
/// metadata plus an override position and animation to apply on match.
///
/// Pattern fields are simple wildcards, not regex: `*` matches any run of
/// characters and every other character is matched literally. Matching is
/// case-insensitive and substring-based (the pattern need only appear within
/// the field). An empty or nil pattern field is *ignored*; a rule with no
/// pattern fields specified matches nothing. Specified fields are combined
/// with logical AND. `position` and `animation` are optional so the editor can
/// leave them nil to mean "keep the default."
public struct Rule: Equatable, Sendable, Codable, Identifiable {
  /// Stable identifier across renames, edits, and reorderings.
  ///
  /// Generated from `UUID()` on first creation and never mutated.
  public let id: String

  /// User-facing label shown in the rule editor.
  ///
  /// Not used for matching; cosmetic only.
  public var name: String

  /// When false, `RuleMatcher` skips this rule entirely.
  ///
  /// Lets the user disable a rule without deleting it.
  public var enabled: Bool

  /// Wildcard pattern matched against the banner's source-app display name
  /// (e.g. `"Slack"`).
  ///
  /// Nil or empty leaves the app unconstrained.
  public var appPattern: String?

  /// Wildcard pattern matched against the resolved bundle identifier
  /// (e.g. `"com.tinyspeck.slackmacgap"`).
  ///
  /// Use this when multiple apps share a display name or when stability
  /// across user-facing renames matters.
  public var bundleIDPattern: String?

  /// Wildcard pattern matched against the banner's title line.
  ///
  /// Nil or empty leaves the title unconstrained.
  public var titlePattern: String?

  /// Wildcard pattern matched against the banner's subtitle line.
  public var subtitlePattern: String?

  /// Wildcard pattern matched against the banner's body text.
  public var bodyPattern: String?

  /// When true, a matching banner is also captured into the always-on-top
  /// pinned-notifications list, in addition to any repositioning the rule performs.
  ///
  /// Defaults to false.
  public var pinsToList: Bool

  /// Position to move the matched banner to.
  ///
  /// Nil falls back to the global default selected from the menu bar.
  public var position: Position?

  /// Animation style for the move.
  ///
  /// Nil falls back to `.none` (snap directly to the target).
  public var animation: Animation?

  /// Memberwise initializer with defaults suitable for the rule editor's
  /// "new rule" button (fresh UUID, blank name, enabled, no patterns,
  /// no overrides).
  public init(
    id: String = UUID().uuidString,
    name: String = "",
    enabled: Bool = true,
    appPattern: String? = nil,
    bundleIDPattern: String? = nil,
    titlePattern: String? = nil,
    subtitlePattern: String? = nil,
    bodyPattern: String? = nil,
    pinsToList: Bool = false,
    position: Position? = nil,
    animation: Animation? = nil
  ) {
    self.id = id
    self.name = name
    self.enabled = enabled
    self.appPattern = appPattern
    self.bundleIDPattern = bundleIDPattern
    self.titlePattern = titlePattern
    self.subtitlePattern = subtitlePattern
    self.bodyPattern = bodyPattern
    self.pinsToList = pinsToList
    self.position = position
    self.animation = animation
  }
}
