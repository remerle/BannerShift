# BannerShift — Project Instructions

These rules apply to all work in this repo. They supplement (not replace) the global engineering instructions.

---

## What this is

A macOS background utility (`LSUIElement=true`, no Dock icon) that repositions native notification banners onto a user-chosen 3x3 grid cell. AppKit + Accessibility (AX) only. No notification rendering, no process injection, no network. Requires Accessibility permission.

Reference docs:
- `README.md` — install, use, release pipeline
- Source-level doc comments — the authoritative description of every public type lives next to its declaration; read those before assuming behavior

## Repo layout

```
Package.swift               SwiftPM manifest (macOS 13+, swift-testing dep)
Makefile                    dev driver — `make help` lists all targets
Sources/BannerShiftCore/    pure value types + logic, no system APIs, fully unit-tested
Sources/BannerShift/        AppKit + AX integration, executable target
Tests/BannerShiftCoreTests/ Swift Testing (`@Test`, `#expect`)
Resources/                  Info.plist, entitlements, AppIcon
scripts/build-dev.sh        universal + ad-hoc-signed .app at build/BannerShift.app
populate-secrets.sh         1Password → .env + .secrets/AuthKey.p8 (gitignored)
release.sh                  Developer ID sign + notarize + staple + package
.github/workflows/          release.yml only (tag-triggered, environment-gated)
```

The Core / executable split is load-bearing: anything that could be unit-tested without system frameworks belongs in `BannerShiftCore`. Don't import `AppKit`, `ApplicationServices`, or `Cocoa` into Core.

## Dev commands

```
make help           # list every target
make build          # debug build
make test           # run the test suite (Swift Testing)
make clean          # remove build artifacts
make format         # apply swift-format in place
make lint           # swift-format check + SwiftLint (no auto-fix)
make format-check   # alias for `make lint`
make analyze        # slow: SwiftLint analyzer rules (unused_declaration, unused_import); not in validate
make validate       # lint + build + test  — pre-merge gate
make dev            # universal ad-hoc-signed .app at build/BannerShift.app
make run            # build + open the .app
make tail-log       # tail ~/Library/Logs/BannerShift.log
make secrets-setup  # first-time machine setup: import Developer ID cert then pull secrets
make secrets        # pull signing secrets from 1Password into .env + .secrets/
make release        # signed, notarized, stapled release build (requires `make secrets`)
```

Always run `make validate` before declaring work complete on a change that touches `Sources/` or `Tests/`. Run `make analyze` periodically (not on every change) to catch dead code and unused imports.

## Swift conventions

Goal: DRY, idiomatic, secure, performant Swift. Prefer reading neighboring code over inventing new patterns.

### Idiomatic

- Swift 5.10 toolchain, macOS 13+ deployment target. Don't gate on newer OS without checking `Package.swift` first
- `public` only on types/methods consumed across the module boundary (BannerShiftCore → BannerShift); everything else is internal or private. The library surface is small and deliberate
- Prefer value types (`struct`, `enum`) over classes. Classes only where reference identity or system-API requirements demand it (e.g. `AppDelegate`, AX observer wrappers)
- Use `final class` for any class that doesn't need subclassing (every class in this repo so far)
- Use `enum` namespaces for static constant groupings (see `Constants.swift`) — never use uninstantiable `struct` or `class` for this
- DocC-style triple-slash comments on public API. Cover intent, contract, and non-obvious caveats; do not restate the signature
- `// MARK: -` to section longer files (see `PositionCalculator.swift`, `BannerMover.swift`)
- Prefer Swift `Regex` (literal `/.../` or builder syntax) over `NSRegularExpression`. User-supplied patterns must be case-insensitive (see `RuleMatcher.swift`)

### DRY (without premature abstraction)

- A single source of truth for OS-dependent magic strings/numbers: `Sources/BannerShiftCore/Constants.swift`. Do not duplicate banner subroles, panel identifiers, or padding values anywhere else
- The Core target is the abstraction layer. If logic in `Sources/BannerShift/*.swift` looks generally useful and has no AppKit/AX dependency, move it to Core and unit-test it
- Three real call sites before extracting a helper. Two duplications is fine; the global principle 9 applies here

### Security

- This is a per-user background agent that reads notification text via AX. Treat notification content as sensitive
- Never write notification body/title/subtitle to disk except when `FileLogger` is explicitly in debug mode (see `FileLogger.swift`). Default log level must not leak content
- Rule patterns are user-supplied Swift `Regex`. Compile once at rule-load time, fail closed (skip the rule, log the error) on invalid patterns — never let a bad rule crash the matcher
- The app must terminate, not silently degrade, on denied Accessibility permission. Don't add a "limp along without AX" mode
- Entitlements stay minimal (`Resources/BannerShift.entitlements`). No new entitlements without a documented reason in the PR that adds them
- For shell scripts (`release.sh`, `populate-secrets.sh`, `scripts/*.sh`): `set -euo pipefail` at the top, `umask 077` before writing any secret material, `trap` cleanup on EXIT for temp files and keychains. Never pass secrets as CLI args

### Performance

- Banner repositioning runs on the main thread in response to AX notifications (high frequency under burst conditions). The `Debouncer` (`Sources/BannerShiftCore/Debouncer.swift`) coalesces event storms at `Constants.eventDebounceInterval` — use it, don't bypass it
- Cache compiled `Regex` per-rule; do not recompile on every match
- `BannerMover.baselines` is keyed by AX element identity (`UInt64`). Keep that map bounded by clearing entries when the corresponding banner disappears (see `reset()`)
- Animations (`Animator.swift`, `AnimationFrames.swift`) are precomputed frame schedules; do not allocate per-frame
- Avoid `Timer.scheduledTimer` for sub-100ms intervals; prefer `DispatchSourceTimer` or precomputed schedules (already established in `Animator.swift`)
- Don't add async/await to AX call sites — the AX API is synchronous-on-main-thread and adding `await` only obscures the threading invariant

## Testing

- Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest. Do not introduce XCTest into this project
- Tests live next to the target they exercise: `Tests/BannerShiftCoreTests/` for Core. The executable target has no unit tests; verify it manually by exercising real macOS notifications against a built `.app`
- Cover the math (coordinate transforms, animation frames, rule matching) exhaustively. Cover orchestration loosely
- Tests must not depend on the host machine's display configuration or current preferences. Construct `ScreenInfo` literals in the test file (see `PositionCalculatorTests.swift`)
- Don't mock `BannerShiftCore` types — they're already pure. Mocking pure code tests the mock framework

## OS fragility — read before touching AX code

BannerShift depends on a small number of undocumented macOS internals. When any of these break across a macOS major release, fix the constant in `Constants.swift` first, then update the affected logic:

- `Constants.bannerSubroles` — AX subroles that identify a banner element
- `Constants.notificationUIBundleIdentifier` — `com.apple.notificationcenterui`
- `Constants.notificationCenterPanelIdentifier` — `widget-editor`, used to distinguish open Notification Center from a transient banner
- The full-screen container window invariant (`PositionCalculator.invariantHolds`) — bail out of repositioning if it stops holding

Adding a workaround for a new macOS version: document the symptom and the macOS version in a comment on the affected constant or invariant so the next maintainer can correlate it to an OS upgrade.

---

## GitHub Actions / CI Practices

These rules are **mandatory** for any GitHub Actions workflow you author or modify in this repo. If asked to violate one, surface a PRINCIPLE CONCERN before proceeding.

### Supply Chain

- Pin third-party actions to a full 40-character commit SHA, never a tag (`@a1b2c3d4e5f6...` not `@v45`). The March 2025 `tj-actions/changed-files` compromise hit ~23,000 repos via retroactive tag rewrites; SHA pinning is the only defense
- First-party actions (`actions/*`) may use major version tags (`@v4`), but SHA is preferred for release/signing workflows
- Add a `# v45.0.4` comment next to each SHA-pinned action so reviewers can spot upgrades

### Secrets and Permissions

- Default workflow-level `permissions: {}` and grant the minimum each job needs. Never rely on the default `GITHUB_TOKEN` having `contents: write`
- Production-credential workflows (signing, notarization, deploy, registry push) MUST be gated behind a GitHub Environment with required reviewers; secrets mount only after human approval
- Scope secrets to environments, not repo-wide
- Never `echo` a secret to logs; use `::add-mask::value` on any derived value before logging
- Use OIDC over long-lived credentials where available (AWS, GCP, Azure). Apple Developer does not support OIDC yet, so long-lived API keys are unavoidable; compensate with environment protection
- Decode base64 secrets into temp files with `umask 077` set first; `trap` cleanup on EXIT

### Untrusted Input

- Never use `pull_request_target` unless the workflow specifically needs PR comment/label access. If used, never check out the PR head SHA in the same job that has secrets access. `pull_request_target` runs with base-repo secrets against fork code; checkout + secrets equals full repo compromise
- Sanitize `${{ github.event.* }}` values flowing into shell steps. Pin them to env vars first and quote `"$VAR"` in bash, rather than direct `${{ }}` interpolation in run blocks

### macOS Signing Specifics

- Use ephemeral keychains for code signing: create with a random password, import the cert, run codesign, then `security delete-keychain`. Never touch the runner's default or login keychain
- Notarization MUST run with `xcrun notarytool submit --wait` and fail-fast on non-`Accepted` status, fetching `notarytool log <id>` for diagnostics before exiting non-zero
- Always staple the ticket with `xcrun stapler staple` and verify with `xcrun stapler validate` after submission
- Run `spctl --assess --type execute -vv` on the final bundle as a smoke check (informational, allowed to fail)

### Concurrency and Idempotency

- Add `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: false }` to release workflows; killing a notarization mid-flight is worse than queuing
- Re-runs on the same tag must produce equivalent artifacts; bake the version from the tag, not from a moving file

### Conventions

- Trigger releases on `push.tags: 'v*'`. The git tag is the version source of truth; the workflow extracts version from `github.ref_name` and injects it into `Info.plist` at build time. Do not derive the version from a file in the repo unless explicitly asked
- Set job-level `timeout-minutes:` on every job; default macOS runner timeout is 6 hours
- Cache Swift build artifacts via `actions/cache` keyed on `Package.resolved` hash

### Watch For

Flag these proactively when reviewing or writing GHA workflows:

- Unpinned third-party actions (`@main`, `@master`, bare major version tag)
- Production secrets mounted without an environment gate
- `pull_request_target` checking out PR head SHA in a secrets-bearing job
- Secrets passed as CLI args (visible in process listings) instead of env vars
- Missing workflow-level `permissions:` block (default is broad-read, sometimes write)
- `actions/checkout` with default `persist-credentials: true` when subsequent steps do not need git push
- Multi-line shell steps missing `set -e` (or `set -euo pipefail`)
- Output values derived from secrets that are not `::add-mask::`'d

---

## Linting and Documentation

These rules apply to any work touching SwiftLint, swift-format, or source-level documentation comments in this repo.

### Pace over throughput

Triaging lint findings is not a race. The cost of a sloppy or wrong fix is higher than the cost of taking another iteration on the same finding.

- Do not bulk-fix findings. Walk them rule-by-rule, file-by-file. Understand each rule's intent before applying a fix to its first site.
- For `missing_docs` violations: write the actual purpose, contract, and any non-obvious caveats. A one-line summary that just restates the function name in prose is not useful documentation. If you cannot say something the signature does not already convey, stop and read the implementation until you can.
- For correctness findings (`force_unwrapping`, `implicitly_unwrapped_optional`, `weak_delegate`, etc.): understand what invariant the rule is protecting. A force-unwrap removed without understanding the invariant becomes a silent crash later; replace it with code that either preserves the invariant or fails clearly when it doesn't hold.
- Keep doc-only changes in their own commits, separate from behavior changes. Doc commits are easier to review and revert.

### Doc-comment quality bar

A doc comment exists to answer questions a reader of the source signature cannot answer from the signature alone. Useful ingredients, in priority order:

- The intent or contract (what does this guarantee; what does it refuse to do)
- The relationship to other code (when is this called, who is supposed to call it)
- Preconditions, side effects, or invariants the type/method depends on
- Failure modes (what does `nil` / `throws` / `false` mean here)
- "Why this exists" framing — link to an external doc or referenced API when relevant

Do not write doc comments that:

- Restate the signature in prose (`/// Returns the user.` for `func user() -> User`)
- Describe self-explanatory parameters (`/// - Parameter id: the id`)
- Include marketing or filler language ("This handy function…")
- Promise behavior the code does not actually deliver

When unsure, read the implementation and write what you wish you had known before reading it.

### Rule suppression is a last resort

This re-emphasizes the global engineering rule "Lint Warnings Are Signal, Not Noise" (`~/.claude-personal/CLAUDE.md` §14) with project-specific binding:

- The default reaction to a lint failure is to fix the code. Suppression is the exception, not the menu.
- A `// swiftlint:disable:next <rule>` is acceptable only when all three hold: the rule genuinely does not apply at that single site, the scope is the single line (no block disables), and a `// Reason:` comment on the preceding line explains why in plain language a reviewer can challenge.
- Never use a file-scoped `// swiftlint:disable <rule>` block. Either fix every site or open a discussion about whether the rule fits the project's conventions.
- Never edit `.swiftlint.yml` or `.swift-format` to globally disable a rule just because it fires across the codebase. If a rule needs to be relaxed, that is a project-policy change: surface it explicitly with a comment in the config file recording the rationale, and call it out in the PR description.
- Never delete code to silence a finding unless you have proved the code is unused by cross-reference search and call-graph tracing. "SwiftLint says it's unused" is a hypothesis until verified — see Chesterton's Fence (global §4).
- The `analyzer_rules` (`unused_declaration`, `unused_import`) are particularly prone to false positives across module boundaries; treat their findings as leads to investigate, not verdicts.
- Every suppression must be visible in the PR description so a reviewer can object.

### When to push back instead of fixing

If a finding cannot be resolved without changing the rule, the convention, or restructuring meaningful code, stop and raise the question rather than guessing. Acceptable outcomes:

- Fix the code to satisfy the rule (default)
- Adjust the rule's configuration in `.swiftlint.yml` with an explicit, documented rationale (rare)
- Disable the rule for a single site with a `// Reason:` comment (rarer)
- Open a discussion about whether the rule fits — do not silently make any of the above changes
