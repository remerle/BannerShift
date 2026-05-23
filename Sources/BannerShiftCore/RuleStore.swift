import Foundation

/// Reference-typed so a single instance can be shared across the app
/// (AppDelegate owns it; BannerMover and the rule editor both hold a
/// reference). The shared instance also holds a decoded-rule cache so
/// repeated `load()` calls during a notification burst do not re-parse
/// the JSON blob on every debounce pass (perf-001 / quality-012).
public final class RuleStore {
  public static let key = "rules"

  private let defaults: UserDefaults
  private let logger: ((String) -> Void)?
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  // nil means "not yet loaded from defaults"; an empty array means
  // "loaded and known empty". The distinction matters so we only emit
  // the first-load info log once per RuleStore lifetime.
  private var cachedRules: [Rule]?

  public init(defaults: UserDefaults = .standard, logger: ((String) -> Void)? = nil) {
    self.defaults = defaults
    self.logger = logger
  }

  public func load() -> [Rule] {
    if let cached = cachedRules { return cached }
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

  public func save(_ rules: [Rule]) {
    do {
      let data = try encoder.encode(rules)
      defaults.set(data, forKey: Self.key)
      cachedRules = rules
    } catch {
      logger?("RuleStore: failed to encode rules (\(error)); not saved")
    }
  }
}
