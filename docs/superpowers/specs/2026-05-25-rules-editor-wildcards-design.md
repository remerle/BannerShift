# Rules Editor: Wildcards, App Chooser, and Matcher/Action Separation

**Status:** Approved design
**Date:** 2026-05-25
**Scope:** `BannerShiftCore` rule-matching semantics (unit-tested) and the AppKit rule edit sheet.

## Goal

Make rule authoring approachable for non-technical users by replacing raw regex with
simple wildcards, letting users pick apps from a chooser instead of typing identifiers,
fixing the "empty rule matches everything" foot-gun, and visually separating *what a rule
matches* from *what it does*.

## Decisions (resolved during brainstorming)

- **Match mode:** substring. A pattern matches if it appears anywhere in the field; `*`
  fills gaps. (No anchoring.)
- **Wildcard scope:** only `*` is special (becomes `.*`). Every other character — including
  `.`, `?`, `^`, `[` — is matched literally. This is *not* full regex.
- **Empty semantics:** an empty field is ignored. A rule with **no** fields specified
  matches **nothing**. When one or more fields are specified, they are AND'd.
- **Chooser:** a `Choose…` button on both the App row and the Bundle ID row. App fills the
  display name; Bundle ID fills the bundle identifier. User decides which to match on.
- **No backward compatibility:** nothing has shipped, so stored rules need no migration and
  there is no deprecation path to preserve.
- **Entitlements:** unchanged. The app is unsandboxed, so `NSOpenPanel` needs no new
  entitlement.

## Architecture

### Core: `WildcardPattern` (new value type)

`Sources/BannerShiftCore/Rules/WildcardPattern.swift`

```
enum WildcardPattern {
  /// Translate a user wildcard into a regex pattern string: each `*`
  /// becomes `.*`; every other character is escaped to match literally.
  /// Substring (unanchored) and case-insensitivity are applied by the caller.
  static func regexPattern(from wildcard: String) -> String
}
```

- Escapes the Swift-regex metacharacters `\ ^ $ . | ? + ( ) [ ] { }` as literals; translates
  `*` to `.*`.
- Pure, no system frameworks, no state. Lives in Core so it is unit-testable.

### Core: `RuleMatcher` changes

- `compileForMatching(_:)` translates the wildcard via `WildcardPattern.regexPattern(from:)`
  before building `Regex(...).ignoresCase().dotMatchesNewlines()`. Signature and name
  unchanged (still used as the single compile entry point). The regex cache key stays the
  raw pattern string (stable per rule).
- `matches(_:_:)` is rewritten:
  - Collect the fields whose pattern is non-nil and non-empty (the *specified* criteria).
  - If none are specified, return `false` (a criteria-less rule matches nothing).
  - Otherwise every specified field must match (logical AND). Unspecified fields are skipped.
- The malformed-pattern diagnostic path is now unreachable for user input (wildcard
  translation always yields a valid regex). Keep the `throws`/`diagnosticLogger` plumbing as
  defense-in-depth (the `Regex` initializer is throwing), but it is no longer exercised by
  user-supplied patterns.

### Core: `Rule` doc comment

Update the type doc to describe the new contract: fields are wildcard patterns (`*` = any
run, everything else literal, case-insensitive, substring); an empty field is ignored;
specified fields are AND'd; a rule with no specified fields matches nothing.

### UI: `RuleEditSheetController`

- **Placeholders:** change the field placeholder from `regex (empty = matches anything)` to
  `* matches anything; empty = ignore`.
- **Remove validation:** delete the regex validation, the red error border, the status
  label, and the Done-button gating. Wildcards are always valid, so Done is always enabled.
  The `NSTextFieldDelegate` live-validation is dropped from this sheet.
- **App/Bundle ID chooser:** a `Choose…` button trailing the App field and the Bundle ID
  field. Each opens an `NSOpenPanel` configured for a single `.application` bundle, defaulting
  to `/Applications`. On selection:
  - App row: fill the App field with `FileManager.displayName(atPath:)` (Finder-style name).
  - Bundle ID row: fill the Bundle ID field with `Bundle(url:)?.bundleIdentifier`.
  - The field and its button sit in a horizontal stack inside the grid's field column; the
    field keeps low hugging (fills), the button takes its natural width on the trailing side.
- **Matcher/action separation:** the sheet is reorganized top-to-bottom as:
  1. Title (`Add Rule` / `Edit Rule`)
  2. Name field, Enabled checkbox (rule basics)
  3. **Match** section header + the five criteria fields (App, Bundle ID, Title, Subtitle,
     Body)
  4. Separator
  5. **Action** section header + Position and Animation popups
  6. Buttons (Cancel / Add or Done), trailing-aligned
  - Section headers are lightweight bold labels (System-Settings style), not titled boxes.
  - The criteria grid and the action grid share a fixed label-column width so their field
    columns line up across sections.

### Test sheet

`RuleTestSheetController` is unchanged structurally; its fields are literal sample banner
text, not patterns. It inherits the new matcher behavior automatically (a rule with no
specified criteria will now report no match).

### Temporary seed

The temporary launch-time seed in `AppDelegate` (UI-iteration scaffolding) uses a
regex-escaped `com\.apple\.mail`; update it to the wildcard form `com.apple.mail`. This
scaffolding is removed before the work is committed regardless.

## Testing

### New: `WildcardPatternTests`

- `*` → `.*`.
- Regex metacharacters are emitted as literals (e.g. `com.apple.mail` stays a literal dot;
  `[x]` is literal text).
- Empty input → empty output.
- Mixed: `Slack*` → `Slack.*`; `*meeting*` → `.*meeting.*`.

### Updated: `RuleMatcherTests`

- `ruleWithNoPatternsIsCatchall` → `ruleWithNoPatternsMatchesNothing` (expect `nil`).
- `allSetPatternsMustMatch`: replace the `^DM` regex anchor with the wildcard `DM*`.
- `bundleIDPatternMatchedAgainstResolvedID`: replace `tinyspeck\.slack` with the literal
  substring `tinyspeck`.
- `dotMatchesNewlinesInBodyPattern`: replace `alice.*bob` with `alice*bob` (so `*` → `.*`
  spans the newline).
- Remove `malformedRegexDoesNotMatch`, `malformedRegexInvokesDiagnosticLogger`, and
  `malformedRuleDoesNotBlockValidNextRule` — malformed input is no longer possible.
- Keep `emptyRulesReturnNil`, `appPatternMatchesCaseInsensitively`, `firstMatchWins`,
  `disabledRuleSkipped`, `invalidateCacheClearsCompiledPatterns`,
  `compileForMatchingAppliesIgnoresCase` (still valid under wildcards).

### Manual (executable target)

Build the dev app, open the edit sheet, confirm: Choose… fills the App / Bundle ID fields;
wildcard matching works in the Test sheet; an empty rule matches nothing; the Match and
Action sections read as distinct groups.

## Out of scope

- `?` single-character wildcard (only `*` is special).
- Regex escape hatch for power users.
- Per-field match previews in the edit sheet (the Test sheet covers testing).

## Changelog

User-visible, under `Unreleased`:

- **Changed:** rule fields now use simple wildcards (`*`) instead of regular expressions; a
  rule with no criteria no longer matches every notification.
- **Added:** Choose… buttons to pick an app for the App and Bundle ID fields.
