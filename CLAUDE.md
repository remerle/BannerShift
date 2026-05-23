# BannerShift — Project Instructions

These rules apply to all work in this repo. They supplement (not replace) the global engineering instructions.

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
