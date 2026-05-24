import Foundation

/// Persistence layer for the user's rule list, backed by a single
/// JSON blob in `UserDefaults`.
///
/// Reference-typed so a single instance can be shared across the app
/// (AppDelegate owns it; BannerMover and the rule editor both hold a
/// reference). The shared instance also holds a decoded-rule cache so
/// repeated `load()` calls during a notification burst do not
/// re-parse the JSON blob on every debounce pass.
public final class RuleStore {
  /// `UserDefaults` key under which the JSON-encoded rule array is
  /// stored.
  public static let key = "rules"

  private let defaults: UserDefaults
  private let logger: ((String) -> Void)?
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  // The "loaded yet?" distinction matters so we only emit the
  // first-load info log once per RuleStore lifetime. A separate flag
  // (rather than `[Rule]?`) lets the cache itself stay non-optional.
  private var cachedRules: [Rule] = []
  private var hasLoaded = false

  /// - Parameters:
  ///   - defaults: The `UserDefaults` instance to read and write.
  ///     Tests pass an isolated suite; production uses `.standard`.
  ///   - logger: Optional sink for one-line operational messages
  ///     (load success, decode failure). Errors are logged but never
  ///     surfaced as throws so the app can keep running with no rules.
  public init(defaults: UserDefaults = .standard, logger: ((String) -> Void)? = nil) {
    self.defaults = defaults
    self.logger = logger
  }

  /// Return the persisted rule list, or `[]` if none has been saved or
  /// the saved blob fails to decode.
  ///
  /// Cached after the first call; subsequent calls return the cache
  /// without re-reading defaults until `save(_:)` updates it.
  public func load() -> [Rule] {
    if hasLoaded { return cachedRules }
    defer { hasLoaded = true }
    guard let data = defaults.data(forKey: Self.key) else {
      cachedRules = []
      return []
    }
    do {
      let rules = try decoder.decode([Rule].self, from: data)
      logger?("RuleStore: loaded \(rules.count) rule(s) from defaults")
      cachedRules = rules
      return rules
    } catch {
      logger?("RuleStore: failed to decode rules (\(error)); starting empty")
      cachedRules = []
      return []
    }
  }

  /// Encode `rules` and write the blob to defaults.
  ///
  /// Updates the cache so a subsequent `load()` returns the same list
  /// without re-decoding. Encoding failures are logged but not thrown,
  /// and on encode failure the cache is **not** updated — `load()` will
  /// continue to return the previously-cached rules until a subsequent
  /// `save(_:)` succeeds. In practice `Rule` is a flat value type with
  /// only `String`/`Bool`/`Optional` fields so `JSONEncoder` cannot
  /// fail; the explicit semantics here matter only for future
  /// non-trivially-encodable additions to `Rule`.
  public func save(_ rules: [Rule]) {
    do {
      let data = try encoder.encode(rules)
      defaults.set(data, forKey: Self.key)
      cachedRules = rules
      hasLoaded = true
    } catch {
      logger?("RuleStore: failed to encode rules (\(error)); not saved")
    }
  }
}
