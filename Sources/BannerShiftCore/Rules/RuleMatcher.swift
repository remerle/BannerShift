import Foundation

/// Result of a successful rule lookup: the `Rule` that matched the
/// banner.
///
/// A struct wrapper (rather than returning the bare `Rule`) leaves
/// room to carry match diagnostics in the future without breaking
/// callers.
public struct RuleMatch: Equatable {
  /// The matched rule.
  ///
  /// Callers read `position` and `animation` from this to override
  /// the global defaults.
  public let rule: Rule

  /// Constructs a match result around the matched rule.
  public init(rule: Rule) { self.rule = rule }
}

/// Matches a `BannerText` against an ordered list of `Rule`s and
/// returns the first match.
///
/// Reference-typed even though every input is passed in per-call: the
/// matcher holds a `[pattern -> compiled Regex]` cache so successive
/// debounced passes do not recompile the same patterns. It is owned by
/// `AppDelegate` (one instance shared with `BannerMover`) and by the
/// rule editor (its own instance), so the cache is amortized across
/// all matches against the same rule set.
///
/// In production all calls are made on the main thread, but the cache
/// is guarded by a lock so a single instance can also be exercised
/// safely from parallel unit tests (Swift Testing runs `@Test`
/// functions on a concurrent executor) and to keep the type robust
/// against future callers on background queues.
public final class RuleMatcher {
  private let diagnosticLogger: ((String) -> Void)?

  // Cache keyed by raw pattern string. Pattern strings are stable for the
  // lifetime of a rule, so a stale entry can only exist if a rule's
  // pattern text is mutated; in that case a fresh entry is compiled on
  // the next call and the old one sits unused. A malformed pattern
  // disables the *containing rule*, not the entire matcher, so we cache
  // successful compilations only and re-attempt failures each call (they
  // are surfaced via `diagnosticLogger` rather than swallowed).
  private var regexCache: [String: Regex<AnyRegexOutput>] = [:]
  private let cacheLock = NSLock()

  /// - Parameter diagnosticLogger: optional sink invoked when a rule's
  ///   pattern fails to compile. A malformed pattern must never be
  ///   silently ignored; the matcher emits a diagnostic and treats the
  ///   containing rule as disabled for that match.
  public init(diagnosticLogger: ((String) -> Void)? = nil) {
    self.diagnosticLogger = diagnosticLogger
  }

  /// Returns the first enabled rule in `rules` whose patterns all match
  /// `banner`, or nil if no rule matches.
  ///
  /// Ordering is significant: callers control priority by ordering
  /// rules in the list. A rule with a malformed regex emits a
  /// diagnostic via the constructor-supplied logger and is treated as
  /// disabled for the duration of the call (so a broken rule never
  /// blocks subsequent valid rules from matching).
  public func match(rules: [Rule], banner: BannerText) -> RuleMatch? {
    for rule in rules where rule.enabled {
      do {
        if try matches(rule, banner) {
          return RuleMatch(rule: rule)
        }
      } catch {
        diagnosticLogger?(
          "RuleMatcher: rule '\(rule.name)' (id=\(rule.id)) has a malformed "
            + "regex; treating as disabled. Error: \(error.localizedDescription)"
        )
        continue
      }
    }
    return nil
  }

  /// Drop all cached compiled patterns.
  ///
  /// Safe to call at any time; the next match call repopulates lazily.
  /// With the keyed-cache approach (entries are correct as long as the
  /// pattern string is unchanged) this is not strictly required, but
  /// exposed for callers that want to bound memory after large
  /// rule-set edits.
  public func invalidateCache() {
    cacheLock.lock()
    defer { cacheLock.unlock() }
    regexCache.removeAll()
  }

  /// Compile `wildcard` into the `Regex` the matcher uses at runtime.
  ///
  /// The pattern is a BannerShift wildcard (`*` = any run, everything else
  /// literal), translated via `WildcardPattern` and compiled with `ignoresCase`
  /// + `dotMatchesNewlines`. Exposed so a future match-equivalence test can
  /// compile against the same semantics the matcher uses.
  public static func compileForMatching(_ wildcard: String) throws -> Regex<AnyRegexOutput> {
    try Regex(WildcardPattern.regexPattern(from: wildcard)).ignoresCase().dotMatchesNewlines()
  }

  private func matches(_ rule: Rule, _ banner: BannerText) throws -> Bool {
    // `bundleID` is the only optional subject: nil means the banner's app
    // could not be resolved to a bundle identifier. It is passed through as
    // nil (not coalesced to "") so a specified `bundleIDPattern` fails to
    // match an unresolved banner — see `check`. Every other field is always
    // present (possibly empty) on a `BannerText`.
    let criteria: [(pattern: String?, subject: String?)] = [
      (rule.appPattern, banner.appName),
      (rule.bundleIDPattern, banner.bundleID),
      (rule.titlePattern, banner.title),
      (rule.subtitlePattern, banner.subtitle),
      (rule.bodyPattern, banner.body),
    ]
    // A rule with no criteria specified matches nothing (not everything).
    let specified = criteria.filter { $0.pattern?.isEmpty == false }
    guard !specified.isEmpty else { return false }
    return try specified.allSatisfy { try check($0.pattern, $0.subject) }
  }

  private func check(_ pattern: String?, _ subject: String?) throws -> Bool {
    guard let pattern, !pattern.isEmpty else { return true }
    // A specified pattern requires the banner field to be present. A nil
    // subject (an unresolved `bundleID`) cannot satisfy any pattern — including
    // a wildcard `*`, which compiles to `.*` and would otherwise match the
    // empty string. Matching here would let a `bundleIDPattern = "*"` rule fire
    // on banners whose bundle ID could not be resolved, contradicting
    // `BannerText.bundleID`'s documented contract.
    guard let subject else { return false }
    let regex = try compiledRegex(for: pattern)
    // Cap the subject length so a pathological-length banner field
    // cannot turn a backtracking-heavy user pattern into a main-thread
    // stall. Real banner text is well under this cap; the truncation
    // is a defense-in-depth measure against malformed or adversarial
    // AX content.
    let bounded =
      subject.count > Constants.maxBannerMatchSubjectLength
      ? String(subject.prefix(Constants.maxBannerMatchSubjectLength))
      : subject
    return bounded.firstMatch(of: regex) != nil
  }

  /// Compile-or-fetch a regex for `pattern`.
  ///
  /// Holds the lock only across the cache lookup/insert; regex
  /// compilation itself happens outside the lock to keep the critical
  /// section short under contention.
  private func compiledRegex(for pattern: String) throws -> Regex<AnyRegexOutput> {
    cacheLock.lock()
    if let cached = regexCache[pattern] {
      cacheLock.unlock()
      return cached
    }
    cacheLock.unlock()

    let compiled = try Self.compileForMatching(pattern)

    cacheLock.lock()
    defer { cacheLock.unlock() }
    // Another thread may have inserted the same pattern while we were
    // compiling; that's harmless — last-writer-wins on identical input
    // produces identical regex, and either entry is correct.
    regexCache[pattern] = compiled
    return compiled
  }
}
