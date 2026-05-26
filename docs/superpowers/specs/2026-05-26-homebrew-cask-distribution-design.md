# Homebrew cask distribution — design

**Date:** 2026-05-26
**Status:** Approved, ready for implementation planning

## Overview

Distribute BannerShift through a personal Homebrew **cask** so users can run:

```bash
brew install --cask remerle/tap/bannershift
```

The cask lives in a new repo, `remerle/homebrew-tap`. The existing
`release.yml` workflow gains a final step that auto-bumps the cask
(version + sha256) on every stable release tag.

Out of scope:
- Submitting to the official `Homebrew/homebrew-cask`. Revisit once the
  project clears the notability bar; the personal tap is forward-compatible
  with that move.
- A formula (CLI install). BannerShift is a GUI `.app` and only ships as a
  notarized `.app`/`.dmg`.

## Why a cask

BannerShift is delivered as a notarized, stapled `.app` inside a notarized,
stapled `.dmg` (see `release.yml`). That is exactly the artifact shape a
Homebrew cask expects to consume. Casks install into `/Applications`, respect
Gatekeeper, and integrate with `brew upgrade`. A formula would mean compiling
from source on the user's machine and would bypass our codesigning pipeline
entirely; we do not want that.

## Distribution artifact

The cask points at the **`.dmg`**, not the `.zip`. Both are notarized and
stapled by the release job. The `.dmg` is the conventional cask artifact:

- The DMG contains a `/Applications` symlink, so `brew install --cask`
  cleanly mounts, copies, unmounts.
- The DMG is itself a signed/notarized artifact, giving Homebrew a second
  Gatekeeper verification point beyond the embedded `.app`.

## The tap repo

**Name:** `remerle/homebrew-tap`
**Visibility:** public (required for `brew tap` over HTTPS without auth).
**Default branch:** `main`.

Layout:

```
homebrew-tap/
├── README.md           # install instructions, what this tap contains
└── Casks/
    └── bannershift.rb
```

Seed `README.md` with the install command and a note that this tap is
auto-maintained by BannerShift's release workflow.

## The cask file

`Casks/bannershift.rb`:

```ruby
cask "bannershift" do
  version "1.0.0"
  sha256 "<sha256 of the .dmg>"

  url "https://github.com/remerle/BannerShift/releases/download/v#{version}/BannerShift-#{version}.dmg",
      verified: "github.com/remerle/BannerShift/"
  name "BannerShift"
  desc "Repositions macOS notification banners onto a 3x3 grid"
  homepage "https://github.com/remerle/BannerShift"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"   # matches macOS 13+ deployment target

  app "BannerShift.app"

  uninstall quit: "com.emerle.BannerShift"

  zap trash: [
    "~/Library/Logs/BannerShift.log",
    "~/Library/Preferences/com.emerle.BannerShift.plist",
    "~/Library/Caches/com.emerle.BannerShift",
    "~/Library/HTTPStorages/com.emerle.BannerShift",
    "~/Library/Saved Application State/com.emerle.BannerShift.savedState",
  ]
end
```

### Field rationale

- `verified:` — required by `brew audit` whenever `url` is interpolated
  rather than a literal string. Pins the trusted source prefix.
- `livecheck` with `:github_latest` — drives the `brew livecheck` ecosystem
  (third-party autobumpers, `brew outdated` heuristics) even though our own
  auto-bump is doing the real update work. Cheap to include.
- `depends_on macos:` — matches the `Package.swift` deployment target;
  Homebrew refuses installation on older macOS rather than letting the user
  install something that won't launch.
- `uninstall quit:` — stops the running agent before file removal so the
  process isn't left orphaned. Login-item registration uses `SMAppService`
  (tied to the bundle), so `quit` + bundle removal is sufficient; there is
  no LaunchAgent plist to unload.
- `zap` paths — derived from the `com.emerle.BannerShift` defaults domain
  documented in `docs/configuration.md` and the documented log file path.
  `Caches/`, `HTTPStorages/`, and `Saved Application State/` are standard
  per-bundle-ID locations macOS may create even when the app doesn't write
  them directly; including them keeps `brew uninstall --zap` complete.

## Auto-bump step in `release.yml`

A new step appended to the existing `release` job, **after the GitHub
release is published and before the `if: always()` keychain-teardown step**.
The teardown will still run regardless of the bump's outcome (it's
`if: always()`), so the bump cannot leak the ephemeral keychain. Placing the
bump after publish means: the release artifacts are the source of truth, and
a bump failure never blocks the release itself.

### Trigger and guard

The step runs only on stable tags. The existing version regex permits
`vX.Y.Z-suffix`, which should not bump the cask:

```yaml
- name: Bump Homebrew cask
  if: ${{ !contains(needs.build.outputs.version, '-') }}
```

### Auth

Checkout the tap with a **fine-grained PAT** stored as
`HOMEBREW_TAP_PAT` in the `release-signing` GitHub Environment. This piggy-
backs on the same manual-approval gate as the signing secrets, so the PAT
is only mounted after a human approves the release run.

PAT scope:
- Repository access: **only** `remerle/homebrew-tap`.
- Permissions: **Contents: Read & write**. Nothing else.

Use `actions/checkout` to set up the auth, not a token-in-URL push. This
keeps the PAT out of any command line or process listing (satisfies the
"secrets as env vars, not CLI args" rule in `CLAUDE.md`):

```yaml
- name: Checkout homebrew-tap
  uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
  with:
    repository: remerle/homebrew-tap
    token: ${{ secrets.HOMEBREW_TAP_PAT }}
    path: homebrew-tap
    persist-credentials: true
```

`persist-credentials: true` is correct here — the subsequent `git push`
needs the credentials to be available. Defaults to true; stated explicitly
so the intent is visible.

### Update logic

```yaml
- name: Update cask and push
  env:
    VERSION: ${{ needs.build.outputs.version }}
  run: |
    set -euo pipefail

    SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
    CASK="homebrew-tap/Casks/bannershift.rb"

    # Targeted replacements on the two version-bearing lines. Anchored to
    # the exact field syntax so unrelated lines can't match.
    /usr/bin/sed -i.bak -E \
      -e "s|^([[:space:]]*version )\"[^\"]*\"|\\1\"${VERSION}\"|" \
      -e "s|^([[:space:]]*sha256 )\"[^\"]*\"|\\1\"${SHA256}\"|" \
      "$CASK"
    rm -f "${CASK}.bak"

    cd homebrew-tap
    git config user.name  "BannerShift Release Bot"
    git config user.email "noreply@github.com"

    if git diff --quiet -- Casks/bannershift.rb; then
      echo "Cask already at ${VERSION}; nothing to push."
      exit 0
    fi

    git add Casks/bannershift.rb
    git commit -m "bannershift ${VERSION}"
    git push origin HEAD:main
```

Idempotency: re-running the workflow on the same tag is a no-op because the
diff check short-circuits when version and sha256 are already current. This
matches the "re-runs on the same tag must produce equivalent artifacts" rule
in `CLAUDE.md`.

`set -euo pipefail` per the GHA conventions in `CLAUDE.md`.

### Failure handling

If the bump step fails (PAT expired, network error, tap repo unavailable):

- The job goes red.
- The GitHub release and uploaded artifacts are already published; they are
  the source of truth and are not rolled back.
- The maintainer fixes the cause and either reruns the release job or
  manually applies the bump to the tap. The cask file is small enough that
  manual recovery is straightforward.

This is consistent with the workflow's overall philosophy: the release
artifacts are immutable once published; the tap is a downstream consumer.

### Permissions

The `release` job already declares `permissions: contents: write` for the
BannerShift repo. The PAT covers the tap repo separately, so no job-level
permission changes are needed.

## Docs

- **README.md** — add a `brew install --cask remerle/tap/bannershift` line
  to the **Install** section, above the manual download instructions. The
  manual download stays for users who don't have Homebrew or want the raw
  artifact.
- **docs/release.md** — document the tap, the auto-bump step, the
  `HOMEBREW_TAP_PAT` secret, and its rotation expectation (fine-grained PATs
  have a maximum lifetime; record when this one expires and how to renew).
- **CHANGELOG** — no entry. Per the project memory note, the changelog is
  not populated during v1 development; v1 release will populate it from the
  full history.
- **homebrew-tap/README.md** — short README in the tap repo: what the tap
  contains, the install command, a note that the cask is auto-maintained by
  the BannerShift release workflow and PRs to it will likely be overwritten
  by the next release.

## Verification

This is an infrastructure change with no `BannerShiftCore` or `BannerShift`
code touched, so there are no unit tests to add. Verification before merging:

- `brew style Casks/bannershift.rb` — passes.
- `brew audit --cask --online bannershift` against the tap locally — passes.
- A real install round-trip on a checkpoint build that the cask points at:
  `brew install --cask remerle/tap/bannershift` →
  launch and exercise the menu →
  `brew uninstall --cask bannershift` (binary gone) →
  `brew uninstall --zap bannershift` (preferences and log gone).
- The auto-bump step is verified by the next real release tag. The
  cross-repo push cannot be dry-run from CI without a live PAT.

## Risks and considered alternatives

- **Direct push vs. PR.** Chose direct push for zero per-release toil; the
  sha256 is computed from the just-notarized artifact in the same job, so
  the failure mode the PR review would catch (wrong checksum) is structurally
  prevented. If the cask grows enough internal logic to warrant review, this
  decision can be revisited without disrupting users.
- **Personal tap vs. `homebrew/cask`.** Personal tap chosen because
  `homebrew/cask` has a notability requirement that a brand-new v1 will not
  clear. The two paths are not mutually exclusive; upstreaming later is
  straightforward (the cask file is portable).
- **`.zip` artifact vs. `.dmg`.** `.dmg` is the conventional choice for GUI
  cask, and both artifacts are produced by the existing release pipeline.
- **GitHub App vs. PAT.** A GitHub App is the strictest-scope option, but
  setup overhead is high for a single tap. A fine-grained PAT scoped to one
  repo with one permission is a good fit. If the tap grows to host more
  casks or other repos start writing to it, revisit the App route.
