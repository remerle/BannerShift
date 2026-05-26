# Bundle Identifier Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the macOS bundle identifier from `com.emerle.BannerShift` to `dev.emerle.bannershift` before v1 ships.

**Architecture:** The bundle identifier flows through a single Core constant (`Constants.bundleIdentifier`) consumed by the os.Logger subsystem, the test notification identifier prefix, and other internal call sites. Updating that constant plus `Info.plist` plus a handful of doc references is the whole change. No migration code is needed because v1 has not yet shipped.

**Tech Stack:** Swift 5.10, SwiftPM, AppKit, macOS unified log (`os.Logger`). Validation runs through the project's existing `make validate` (swift-format + SwiftLint + build + Swift Testing).

**Spec:** `docs/superpowers/specs/2026-05-26-bundle-id-rename-design.md`

**TDD note:** This change is not TDD-shaped. The bundle identifier is a constant string; no existing test pins its value, and adding `#expect(Constants.bundleIdentifier == "dev.emerle.bannershift")` would only restate the constant (a tautology, not a behavior assertion). Verification is `make validate` (catches typos and broken downstream consumers) plus a manual smoke build that confirms the new identifier is live end-to-end. The plan is structured accordingly: small, ordered code edits followed by validate and a smoke build, not red-green-refactor cycles.

---

## File Structure

| File | Action | Why it changes |
| --- | --- | --- |
| `Sources/BannerShiftCore/Support/Constants.swift` | Modify line 15 | The single source of truth. Every internal consumer (`os.Logger` subsystems, test notification identifier prefix, etc.) reads `Constants.bundleIdentifier`, so updating this one constant cascades everywhere. |
| `Resources/Info.plist` | Modify line 7 | The macOS-level `CFBundleIdentifier`. Must match `Constants.bundleIdentifier`. |
| `Sources/BannerShiftCore/Support/Preferences.swift` | Modify line 59 | Doc-comment example references the old domain in a `defaults write …` invocation. |
| `docs/configuration.md` | Modify 4 references | User-facing docs: the "defaults domain" callout, two `defaults write` examples, one `log stream` predicate example. |
| `README.md` | Modify 1 reference | One `defaults write` example in the troubleshooting section. |

**Commits:** two — one for source + plist + Preferences doc-comment (the code change), one for the user-facing doc sweep. Keeping docs separate honors the project's "doc-only changes in their own commits" guidance from `CLAUDE.md` and makes `git bisect` cleaner.

---

## Task 1: Baseline check

Confirm the current branch is clean and `make validate` passes before any edit. This establishes that any later failure is attributable to this change.

**Files:** none modified.

- [ ] **Step 1: Confirm clean working tree**

Run:

```bash
git status --short
```

Expected: no output (clean).

- [ ] **Step 2: Confirm baseline validate passes**

Run:

```bash
make validate
```

Expected: PASS (lint + build + tests all green). If this fails before any edit, stop and surface the failure; do not proceed with the rename until the baseline is green.

---

## Task 2: Rename the bundle identifier in code

This is the load-bearing edit. Update `Constants.bundleIdentifier` (the single source of truth), `CFBundleIdentifier` in `Info.plist`, and the one doc-comment that hard-codes the old value as a CLI example.

**Files:**
- Modify: `Sources/BannerShiftCore/Support/Constants.swift:15`
- Modify: `Resources/Info.plist:7`
- Modify: `Sources/BannerShiftCore/Support/Preferences.swift:59`

- [ ] **Step 1: Update the Core constant**

In `Sources/BannerShiftCore/Support/Constants.swift`, change line 15:

```swift
  public static let bundleIdentifier = "com.emerle.BannerShift"
```

to:

```swift
  public static let bundleIdentifier = "dev.emerle.bannershift"
```

Do not touch the surrounding doc comment; it still describes accurately what the constant is.

- [ ] **Step 2: Update Info.plist**

In `Resources/Info.plist`, change line 7:

```xml
    <key>CFBundleIdentifier</key>                 <string>com.emerle.BannerShift</string>
```

to:

```xml
    <key>CFBundleIdentifier</key>                 <string>dev.emerle.bannershift</string>
```

Preserve the existing column alignment of the value. After saving, verify the plist still parses:

```bash
plutil -lint Resources/Info.plist
```

Expected: `Resources/Info.plist: OK`.

- [ ] **Step 3: Update the Preferences doc-comment example**

In `Sources/BannerShiftCore/Support/Preferences.swift`, change line 59 from:

```swift
  /// `defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES`
```

to:

```swift
  /// `defaults write dev.emerle.bannershift debugLoggingEnabled -bool YES`
```

- [ ] **Step 4: Verify no stale references remain in code**

Run:

```bash
grep -rn -E '(com\.emerle\.BannerShift|com\.emerle\.bannershift)' \
  --include='*.swift' --include='*.plist' --include='*.entitlements' \
  Sources/ Resources/ Tests/
```

Expected: no matches. If anything is returned, fix it before proceeding.

- [ ] **Step 5: Run `make validate`**

Run:

```bash
make validate
```

Expected: PASS. The build link/run succeeds, swift-format and SwiftLint stay clean, all `BannerShiftCoreTests` pass. The os.Logger subsystem and test notification identifier prefix now reference the new identifier automatically because they read `Constants.bundleIdentifier`.

- [ ] **Step 6: Commit the code change**

```bash
git add \
  Sources/BannerShiftCore/Support/Constants.swift \
  Sources/BannerShiftCore/Support/Preferences.swift \
  Resources/Info.plist
git commit -m "Rename bundle identifier to dev.emerle.bannershift

- Update Constants.bundleIdentifier (single source of truth for os.Logger
  subsystem, test notification prefix, and UserDefaults domain)
- Update CFBundleIdentifier in Info.plist to match
- Update the defaults-write example in the Preferences doc comment
- No migration code: v1 has not shipped, so no end user has prefs or login
  items keyed to the old identifier"
```

---

## Task 3: Update user-facing docs

Sweep the two markdown files that mention the old identifier in command examples and prose.

**Files:**
- Modify: `docs/configuration.md` (4 references)
- Modify: `README.md:120`

- [ ] **Step 1: Update `docs/configuration.md`**

Make four edits.

**1.** Around line 8, change:

```markdown
The defaults domain (and bundle identifier) is **`com.emerle.BannerShift`**.
```

to:

```markdown
The defaults domain (and bundle identifier) is **`dev.emerle.bannershift`**.
```

**2.** Around lines 26–27, change:

```bash
defaults write com.emerle.BannerShift selectedPosition -string "bottom-right"
defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES
```

to:

```bash
defaults write dev.emerle.bannershift selectedPosition -string "bottom-right"
defaults write dev.emerle.bannershift debugLoggingEnabled -bool YES
```

**3.** Around line 33, change:

```markdown
`com.emerle.BannerShift` defaults domain (not a standalone file). Edit them
```

to:

```markdown
`dev.emerle.bannershift` defaults domain (not a standalone file). Edit them
```

**4.** Around line 147, change:

```bash
log stream --predicate 'subsystem == "com.emerle.BannerShift"' --level info
```

to:

```bash
log stream --predicate 'subsystem == "dev.emerle.bannershift"' --level info
```

- [ ] **Step 2: Update `README.md`**

Around line 120, change:

```markdown
`defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES`, reproduce
```

to:

```markdown
`defaults write dev.emerle.bannershift debugLoggingEnabled -bool YES`, reproduce
```

- [ ] **Step 3: Verify no stale references remain anywhere**

Run:

```bash
grep -rn -E '(com\.emerle\.BannerShift|com\.emerle\.bannershift)' \
  --include='*.swift' --include='*.plist' --include='*.entitlements' \
  --include='*.md' --include='*.sh' --include='*.yml' --include='Makefile' \
  --include='*.json' . 2>/dev/null \
  | grep -v '^\./\.build/' | grep -v '^\./build/' \
  | grep -v '^\./docs/superpowers/specs/2026-05-26-bundle-id-rename-design.md' \
  | grep -v '^\./docs/superpowers/plans/2026-05-26-bundle-id-rename.md'
```

Expected: no matches. The spec and plan documents are excluded because they intentionally reference both the old and new identifiers for historical context.

- [ ] **Step 4: Commit the docs sweep**

```bash
git add docs/configuration.md README.md
git commit -m "Update docs to reference new bundle identifier

- docs/configuration.md: defaults-domain callout, two defaults-write
  examples, and the log-stream subsystem predicate
- README.md: the defaults-write example in troubleshooting"
```

---

## Task 4: Manual smoke verification

Build a fresh dev app and confirm the new identifier is live end-to-end. These are the verification commands from the spec, run for real.

**Files:** none modified.

- [ ] **Step 1: Build a fresh universal dev app**

Run:

```bash
make dev
```

Expected: produces `build/BannerShift.app`. If a previous build is cached, you may want `make clean && make dev` to be sure the new identifier is baked into the freshly compiled bundle.

- [ ] **Step 2: Confirm the bundle's identifier per macOS metadata**

Run:

```bash
mdls -name kMDItemCFBundleIdentifier build/BannerShift.app
```

Expected:

```
kMDItemCFBundleIdentifier = "dev.emerle.bannershift"
```

If the value still shows the old identifier, Spotlight indexing may be stale; force a rebuild with `mdimport build/BannerShift.app` and re-run.

- [ ] **Step 3: Confirm UserDefaults is written under the new domain**

Open the freshly built app, change the default position from the menu bar to something other than the current value, then run:

```bash
defaults read dev.emerle.bannershift
```

Expected: at least a `selectedPosition` entry showing the value you just picked, in a domain that did not previously exist on this machine.

If you also want to confirm the os.Logger subsystem flipped:

```bash
log stream --predicate 'subsystem == "dev.emerle.bannershift"' --level info
```

Then exercise the app (send a test notification from the menu). Expected: at least one log line streams under the new subsystem.

- [ ] **Step 4 (optional): Clean up stale local state from the old identifier**

If you previously ran any dev build of BannerShift on this machine, the old identifier left state behind:

```bash
defaults delete com.emerle.BannerShift 2>/dev/null
rm -f ~/Library/Logs/BannerShift.log   # filename unchanged; old contents reference the old subsystem
```

If you ever enabled Launch at Login on an old build, also: **System Settings → General → Login Items** and remove the stale "BannerShift" entry. The freshly built app re-registers itself under the new identifier the next time you toggle Launch at Login on.

- [ ] **Step 5: Final state check**

Run:

```bash
git status --short
git log --oneline -5
```

Expected: clean working tree, two new commits on top of the previous HEAD — the code commit and the docs commit, in that order.

---

## Done criteria

- `make validate` passes.
- `mdls -name kMDItemCFBundleIdentifier build/BannerShift.app` returns `"dev.emerle.bannershift"`.
- `grep -rn 'com\.emerle\.BannerShift' Sources/ Resources/ Tests/ docs/ README.md` returns nothing (the spec and plan files are allowed to mention the old identifier).
- Two commits land on `feature/v1-implementation`: one source-and-plist commit, one docs commit.
