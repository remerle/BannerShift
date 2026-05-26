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

**Name:** `remerle/homebrew-tap` (the `homebrew-` prefix is required by
Homebrew; the suffix is free-form).
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

## Auto-bump workflow (`.github/workflows/bump-cask.yml`)

The bump lives in a **separate workflow** that triggers on
`release: types: [published]`, NOT in the existing `release.yml`. Reason:
`release.yml` creates a **draft** release (`gh release create --draft`);
the maintainer publishes manually after editing notes. The `.dmg` asset URL
returns 404 to unauthenticated users while the release is a draft, so a
bump pushed before publication would advertise a broken cask. Triggering on
`release.published` runs the bump only after the artifacts are publicly
downloadable.

Side benefits of the separate workflow:

- No access to signing secrets — smaller blast radius for the tap PAT.
- The prerelease guard is a clean
  `if: ${{ !github.event.release.prerelease }}`, no version-string parsing.
- A bump failure cannot affect the signing pipeline.

### Trigger and guard

```yaml
on:
  release:
    types: [published]

permissions: {}

concurrency:
  group: bump-cask-${{ github.event.release.tag_name }}
  cancel-in-progress: false

jobs:
  bump:
    if: ${{ !github.event.release.prerelease }}
    name: Bump Homebrew cask
    runs-on: ubuntu-latest      # No macOS-specific tools needed; cheaper.
    timeout-minutes: 10
    environment:
      name: homebrew-tap-bump
    permissions:
      contents: read            # this repo only; tap write is via PAT.
```

### Auth

Checkout the tap with a **fine-grained PAT** stored as `HOMEBREW_TAP_PAT`
in a new GitHub Environment named **`homebrew-tap-bump`** with required
reviewers (the maintainer). Approval is requested per bump run; the
approval friction is small (one click) and gives a clean audit trail
distinct from signing approvals.

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

The workflow derives the version from the release tag and the sha256 from
the released asset (downloading it from the public release URL — the
release is `published` by the time this trigger fires).

```yaml
- name: Download released .dmg
  env:
    TAG: ${{ github.event.release.tag_name }}
    VERSION: ${{ github.event.release.tag_name }}    # stripped below
  run: |
    set -euo pipefail
    VERSION="${TAG#v}"
    DMG_URL="https://github.com/${{ github.repository }}/releases/download/${TAG}/BannerShift-${VERSION}.dmg"
    curl --fail --location --silent --show-error \
      --output "BannerShift-${VERSION}.dmg" "$DMG_URL"
    SHA256="$(shasum -a 256 "BannerShift-${VERSION}.dmg" | awk '{print $1}')"
    echo "VERSION=${VERSION}" >> "$GITHUB_ENV"
    echo "SHA256=${SHA256}"   >> "$GITHUB_ENV"

- name: Update cask and push
  working-directory: homebrew-tap
  run: |
    set -euo pipefail
    CASK="Casks/bannershift.rb"

    # Targeted replacements on the two version-bearing lines. Anchored to
    # the exact field syntax so unrelated lines can't match.
    /usr/bin/sed -i.bak -E \
      -e "s|^([[:space:]]*version )\"[^\"]*\"|\\1\"${VERSION}\"|" \
      -e "s|^([[:space:]]*sha256 )\"[^\"]*\"|\\1\"${SHA256}\"|" \
      "$CASK"
    rm -f "${CASK}.bak"

    git config user.name  "BannerShift Release Bot"
    git config user.email "noreply@github.com"

    if git diff --quiet -- "$CASK"; then
      echo "Cask already at ${VERSION}; nothing to push."
      exit 0
    fi

    git add "$CASK"
    git commit -m "bannershift ${VERSION}"
    git push origin HEAD:main
```

Idempotency: re-publishing the same release (or re-running the workflow)
is a no-op because the diff check short-circuits when version and sha256
are already current.

`set -euo pipefail` per the GHA conventions in `CLAUDE.md`. The
`${{ github.event.release.tag_name }}` value flows through an env var
(`TAG`) rather than direct interpolation into shell, satisfying the
"sanitize event values via env" rule.

### Failure handling

If the bump workflow fails (PAT expired, network error, tap repo
unavailable):

- The workflow run goes red.
- The GitHub release and uploaded artifacts are already published; they are
  the source of truth and are not rolled back.
- The maintainer fixes the cause and either reruns the bump workflow from
  the Actions tab or manually applies the bump to the tap. The cask file is
  small enough that manual recovery is straightforward.

This is consistent with the project's overall philosophy: the release
artifacts are immutable once published; the tap is a downstream consumer.

### Permissions

The workflow declares `permissions: contents: read` at the job level (this
repo only). All tap-repo writes go through the PAT, scoped only to
`remerle/homebrew-tap`.

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

- **Separate workflow vs. step in `release.yml`.** Initially planned as a
  step in the existing `release` job. Revisited when we noticed
  `release.yml` only creates a **draft** release; publication is manual.
  Bumping the cask before the maintainer publishes the draft would point
  the cask at an asset URL that returns 404 to unauthenticated users.
  Triggering on `release.published` removes that window and as a bonus
  isolates the bump from signing secrets.
- **Direct push vs. PR.** Chose direct push for zero per-release toil; the
  sha256 is computed from the just-published artifact downloaded via
  `curl --fail`, so the failure mode a PR review would catch (wrong
  checksum) is structurally prevented. If the cask grows enough internal
  logic to warrant review, this decision can be revisited without
  disrupting users.
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
