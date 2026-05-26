# Bundle Identifier Rename — Design

**Status:** Approved, ready for implementation plan
**Date:** 2026-05-26
**Author:** Q + Claude

## Goal

Rename the macOS bundle identifier from `com.emerle.BannerShift` to `dev.emerle.bannershift` before v1 ships.

## Motivation

- The operator owns `emerle.dev` and `emerle.net` but not `emerle.com`. The current `com.emerle.*` identifier claims a domain the operator does not control; `dev.emerle.*` reverse-DNSes a domain the operator owns, which is what the macOS bundle-identifier convention is for.
- Lowercase identifiers are the modern macOS convention.
- This is the last opportunity to make the change cleanly: `feature/v1-implementation` has not yet been tagged, so no end users have prefs, login-item registrations, or log subsystems bound to the old identifier.

## Non-goals

- Renaming the product or app display name. Both stay `BannerShift`.
- Renaming the SwiftPM executable target (`BannerShift`) or the repo (`BannerShift`).
- Code to migrate the operator's stale local state from the old identifier. A one-time manual cleanup on the dev machine is sufficient and documented below.
- Any change to entitlements, signing, notarization, or release tooling. Developer ID signing is keyed on the team/identity, not the bundle ID.

## Scope: every file that changes

The bundle ID flows through one constant in Core, which everything else consumes. The complete set of touchpoints is:

### Source

- `Sources/BannerShiftCore/Support/Constants.swift:15`
  Change `public static let bundleIdentifier = "com.emerle.BannerShift"` to `"dev.emerle.bannershift"`. This is the single source of truth.
- `Sources/BannerShiftCore/Support/Preferences.swift:59`
  Update the `defaults write …` example inside the doc comment to use the new domain.

### Resources

- `Resources/Info.plist:7`
  Change `CFBundleIdentifier` to `dev.emerle.bannershift`.

### Documentation

- `docs/configuration.md` — four references:
  - The "defaults domain (and bundle identifier) is …" callout
  - The two `defaults write com.emerle.BannerShift …` examples
  - The `log stream --predicate 'subsystem == "com.emerle.BannerShift"'` example
- `README.md:120` — one `defaults write com.emerle.BannerShift …` example.

Nothing else needs to change. The os.Logger subsystem (`AppDelegate.swift`, `FileLogger.swift`), the test notification identifier prefix (`TestNotification.swift`), and any other internal consumer already reads `Constants.bundleIdentifier`, so they pick up the new value automatically.

## Things deliberately left alone

- `Resources/BannerShift.entitlements` — does not reference the bundle ID.
- `scripts/populate-secrets.sh`, `scripts/release.sh`, `.github/workflows/release.yml` — reference the Developer ID identity, App Store Connect key/issuer IDs, and tag-derived version, none of which depend on the bundle ID.
- The log file path `~/Library/Logs/BannerShift.log` — derived from the product name, not the bundle ID. Unchanged.
- Tests — no test pins the bundle-identifier string.

## Knock-on effects

- **Homebrew cask design (separate spec, in-progress):** the cask's `zap` cleanup paths must reference `dev.emerle.bannershift` once the cask is authored. That spec will pick up the new value; this rename does not need to wait for it.
- **os.Logger subsystem** changes from `com.emerle.BannerShift` to `dev.emerle.bannershift`. Any saved Console.app or `log stream` filters keyed to the old subsystem will stop matching. Only the operator has any of these.
- **Operator's local state** (one machine) is now orphaned under the old identifier. See manual cleanup below.

## Manual cleanup, one-time, on the operator's dev machine

After the rename lands and a new build is launched:

```bash
defaults delete com.emerle.BannerShift 2>/dev/null
# If Launch at Login was ever enabled on an old dev build:
#   System Settings → General → Login Items → remove the stale "BannerShift" entry
rm -f ~/Library/Logs/BannerShift.log   # optional; filename is unchanged but old lines reference the old subsystem
```

These do not need to live in code: the rename ships before v1, so no end user is ever in this state. Adding migration code for one machine's local cruft violates "build for the number of users you have."

## Implementation order

The change is mechanical and contained, but the order matters for `make validate`:

1. Update `Constants.swift` (the source of truth).
2. Update `Info.plist`.
3. Update the doc comment in `Preferences.swift`.
4. Update `docs/configuration.md` and `README.md` references.
5. Run `make validate` (lint + build + test). All tests should pass unchanged.

Each step is small enough to share one commit, but the doc changes can be split into a follow-up commit if that reads better in review.

## Verification

After `make validate` passes, build and launch the dev app to confirm the new identifier is live end-to-end:

```bash
make dev
open build/BannerShift.app
mdls -name kMDItemCFBundleIdentifier build/BannerShift.app
# expect: kMDItemCFBundleIdentifier = "dev.emerle.bannershift"

# Change a setting via the menu, then:
defaults read dev.emerle.bannershift
# expect: at least selectedPosition keyed under the new domain

# Confirm the log subsystem moved:
log stream --predicate 'subsystem == "dev.emerle.bannershift"' --level info
# expect: lines appearing as the app does work
```

## Changelog

Per the operator's "no CHANGELOG entries during v1 dev" preference, this rename does not produce a CHANGELOG entry. From the v1 user's perspective there is no prior identifier to migrate from.

## Risks

Low. The rename is a one-line constant change plus a one-line plist change plus documentation. The only realistic regression is a stray hard-coded reference to the old identifier that the touchpoint grep missed; `make validate` plus the post-build `mdls` / `defaults read` checks catch that immediately.
