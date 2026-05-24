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

  /// Compile `pattern` with the exact option set the matcher applies at
  /// runtime (`ignoresCase` + `dotMatchesNewlines`).
  ///
  /// Provided so the rule editor's syntax validator and any future
  /// match-equivalence test can compile against the same semantics the
  /// matcher uses. A bare `Regex(pattern)` reports a pattern as
  /// "valid" without revealing that inline `(?-i)` will be silently
  /// overridden or that `.` will span newlines at runtime.
  public static func compileForMatching(_ pattern: String) throws -> Regex<AnyRegexOutput> {
    try Regex(pattern).ignoresCase().dotMatchesNewlines()
  }

  private func matches(_ rule: Rule, _ banner: BannerText) throws -> Bool {
    try check(rule.appPattern, banner.appName)
      && check(rule.bundleIDPattern, banner.bundleID ?? "")
      && check(rule.titlePattern, banner.title)
      && check(rule.subtitlePattern, banner.subtitle)
      && check(rule.bodyPattern, banner.body)
  }

  private func check(_ pattern: String?, _ subject: String) throws -> Bool {
    guard let pattern, !pattern.isEmpty else { return true }
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
