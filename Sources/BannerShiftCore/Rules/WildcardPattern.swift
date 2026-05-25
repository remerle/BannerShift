import Foundation

/// Translates a user-facing wildcard pattern into a regex pattern string.
///
/// BannerShift rule fields accept simple wildcards rather than full regular
/// expressions: `*` matches any run of characters and every other character is
/// matched literally. This keeps rule authoring approachable while still
/// reusing the `Regex` engine for the actual comparison. The result is meant
/// to be compiled unanchored (substring) and case-insensitively; `RuleMatcher`
/// applies those options, not this type.
public enum WildcardPattern {
  /// Regex metacharacters escaped so they match literally. `*` is excluded on
  /// purpose: it is the one wildcard character and is translated to `.*`.
  private static let metacharacters: Set<Character> = [
    "\\", "^", "$", ".", "|", "?", "+", "(", ")", "[", "]", "{", "}",
  ]

  /// Translate `wildcard` into a regex pattern string: each `*` becomes `.*`;
  /// every other character is emitted literally (metacharacters escaped).
  public static func regexPattern(from wildcard: String) -> String {
    var pattern = ""
    for character in wildcard {
      if character == "*" {
        pattern += ".*"
      } else if metacharacters.contains(character) {
        pattern.append("\\")
        pattern.append(character)
      } else {
        pattern.append(character)
      }
    }
    return pattern
  }
}
