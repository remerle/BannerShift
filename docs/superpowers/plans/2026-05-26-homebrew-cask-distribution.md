# Homebrew Cask Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distribute BannerShift via a personal Homebrew tap so users can run `brew install --cask remerle/tap/bannershift`, with the cask auto-bumped by a workflow that fires when a GitHub release is published.

**Architecture:** A new repo `remerle/homebrew-tap` (created manually, out of band) hosts `Casks/bannershift.rb`. A new workflow `.github/workflows/bump-cask.yml` in this repo triggers on `release: types: [published]`, downloads the published `.dmg`, computes its sha256, rewrites the cask's `version` and `sha256` fields, and pushes directly to the tap using a fine-grained PAT scoped only to that repo. The bump runs only after the maintainer publishes the draft release that `release.yml` creates — guaranteeing the cask never advertises an asset URL that returns 404.

**Tech Stack:** GitHub Actions (Ubuntu runner), Bash, Homebrew cask DSL (Ruby; one short file, no executable Ruby logic).

**Spec:** `docs/superpowers/specs/2026-05-26-homebrew-cask-distribution-design.md`

**TDD note:** This change is not TDD-shaped. The artifacts are a YAML workflow, a Ruby cask DSL file, and prose docs — none of which are unit-testable in the usual sense. The plan substitutes targeted static validation at each step: `actionlint` on the workflow YAML, `shellcheck` (which `actionlint` shells out to) on the embedded bash, and `brew style` / `brew audit --cask` on the cask. End-to-end verification — confirming the workflow actually pushes a correct cask — requires a real release tag with a real PAT, so it cannot land in this plan; the plan documents the manual smoke-test once the first post-merge release ships.

---

## File Structure

| File | Action | Why it changes |
| --- | --- | --- |
| `.github/workflows/bump-cask.yml` | **Create** | The new workflow that auto-bumps the cask when a release is published. |
| `README.md` | Modify | Add a `brew install --cask` line to the Install section, above the manual download. |
| `docs/release.md` | Modify | Document the tap, the `bump-cask.yml` workflow, the `homebrew-tap-bump` environment, the `HOMEBREW_TAP_PAT` secret, and its rotation expectation. |

**Out of repo (manual setup, documented in Task 5):**

- `remerle/homebrew-tap` GitHub repo — created, seeded with `Casks/bannershift.rb` and `README.md`.
- A fine-grained PAT scoped to `remerle/homebrew-tap` with Contents: Read & write.
- A `homebrew-tap-bump` GitHub Environment on this repo with required reviewers and the PAT stored as `HOMEBREW_TAP_PAT`.

**Commits:** four — one per in-repo task. The manual setup (Task 5) is action-only, no commits in this repo.

---

## Task 1: Baseline check

Confirm the working tree is clean and the project still validates before adding the workflow. Establishes that any later failure is attributable to this change.

**Files:** none modified.

- [ ] **Step 1: Confirm clean working tree**

Run:

```bash
git status --short
```

Expected: no output (clean).

- [ ] **Step 2: Confirm baseline `make validate` passes**

Run:

```bash
make validate
```

Expected: PASS. If it fails before any edit, stop and surface the failure; do not proceed.

- [ ] **Step 3: Ensure `actionlint` is installed**

`actionlint` is the lint tool we use to validate the new workflow. Check whether it is available:

```bash
command -v actionlint || brew install actionlint
```

Expected: `actionlint` resolves to a path on `$PATH` (either pre-existing or just installed).

---

## Task 2: Create the cask-bump workflow

The new workflow lives in `.github/workflows/bump-cask.yml`. It is independent from `release.yml`: triggered by `release: types: [published]`, runs on `ubuntu-latest`, uses no signing secrets, and writes only via the tap PAT mounted from the `homebrew-tap-bump` environment.

**Files:**
- Create: `.github/workflows/bump-cask.yml`

- [ ] **Step 1: Create the workflow file**

Write the file `.github/workflows/bump-cask.yml` with this exact content:

```yaml
name: Bump Homebrew cask

# Fires when a GitHub release is published (the manual click on the draft
# that release.yml creates). Triggering on release.published — rather than
# adding a step inside release.yml — ensures the cask is only updated once
# the .dmg asset URL is publicly downloadable. Bumping while the release is
# still a draft would point users at a URL that returns 404 to anyone not
# signed in to GitHub.
on:
  release:
    types: [published]

# Default: no permissions. The job below opts in to what it needs.
permissions: {}

# Never run two bumps against the same tag concurrently. Queuing is safe;
# cancelling mid-push is not.
concurrency:
  group: bump-cask-${{ github.event.release.tag_name }}
  cancel-in-progress: false

jobs:
  bump:
    # Skip GitHub-marked prereleases. The version-regex in release.yml
    # already allows vX.Y.Z-suffix tags; if a maintainer marks a release as
    # prerelease in the publish UI, we honor that and do not advertise it
    # via Homebrew.
    if: ${{ !github.event.release.prerelease }}
    name: Bump Homebrew cask
    runs-on: ubuntu-latest
    timeout-minutes: 10
    # The environment provides the manual-approval gate AND scopes the PAT
    # to just this workflow. Configure required reviewers and the
    # HOMEBREW_TAP_PAT secret under Settings > Environments.
    environment:
      name: homebrew-tap-bump
    permissions:
      # The PAT writes to the tap repo; this job needs no write access to
      # the BannerShift repo itself.
      contents: read
    steps:
      - name: Checkout homebrew-tap
        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          repository: remerle/homebrew-tap
          token: ${{ secrets.HOMEBREW_TAP_PAT }}
          path: homebrew-tap
          persist-credentials: true

      - name: Download released .dmg and compute sha256
        env:
          # Pin event values to env vars before they reach shell, per the
          # GHA conventions in CLAUDE.md.
          TAG: ${{ github.event.release.tag_name }}
          REPO: ${{ github.repository }}
        run: |
          set -euo pipefail
          VERSION="${TAG#v}"
          DMG_NAME="BannerShift-${VERSION}.dmg"
          DMG_URL="https://github.com/${REPO}/releases/download/${TAG}/${DMG_NAME}"
          curl --fail --location --silent --show-error \
            --output "$DMG_NAME" "$DMG_URL"
          SHA256="$(shasum -a 256 "$DMG_NAME" | awk '{print $1}')"
          echo "VERSION=${VERSION}" >> "$GITHUB_ENV"
          echo "SHA256=${SHA256}"   >> "$GITHUB_ENV"

      - name: Update cask file
        working-directory: homebrew-tap
        run: |
          set -euo pipefail
          CASK="Casks/bannershift.rb"

          # Anchored to the exact field syntax so unrelated lines (a future
          # `version` inside a comment, etc.) can't match. The .bak suffix
          # keeps sed portable; we delete it immediately.
          /usr/bin/sed -i.bak -E \
            -e "s|^([[:space:]]*version )\"[^\"]*\"|\\1\"${VERSION}\"|" \
            -e "s|^([[:space:]]*sha256 )\"[^\"]*\"|\\1\"${SHA256}\"|" \
            "$CASK"
          rm -f "${CASK}.bak"

      - name: Commit and push
        working-directory: homebrew-tap
        run: |
          set -euo pipefail
          CASK="Casks/bannershift.rb"

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

- [ ] **Step 2: Lint the workflow with `actionlint`**

Run:

```bash
actionlint .github/workflows/bump-cask.yml
```

Expected: no output (lint clean). `actionlint` will also shell out to `shellcheck` for embedded `run:` blocks if `shellcheck` is on `$PATH`, so this single command covers both YAML and bash.

If `actionlint` reports issues, fix them inline before continuing. Do NOT add `# shellcheck disable=` or `# actionlint:` ignores; the workflow is short enough that any real finding should be resolved by changing the code.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/bump-cask.yml
git commit -m "Add workflow to auto-bump Homebrew cask on release.published

- Triggers when a GitHub release is published (not on tag push), so the
  cask is only updated after the maintainer publishes the draft created
  by release.yml; avoids advertising a .dmg URL that 404s while draft
- Runs on ubuntu-latest with no signing secrets; tap write goes through
  a fine-grained PAT mounted from a new homebrew-tap-bump environment
- Idempotent: re-publishing the same release is a no-op via git diff check"
```

---

## Task 3: Add Homebrew install instructions to `README.md`

The README's Install section currently lists "Download a release" and "Or build it yourself." Add a Homebrew option as the new first choice — easiest path goes first (pit-of-success).

**Files:**
- Modify: `README.md` (Install section)

- [ ] **Step 1: Update the Install section**

Find the section that currently begins:

```markdown
## Install

### Download a release
```

Replace it with:

```markdown
## Install

### With Homebrew (recommended)

```bash
brew install --cask remerle/tap/bannershift
```

`brew upgrade --cask bannershift` updates to the latest release.

### Download a release
```

(Everything below `### Download a release` stays unchanged.)

- [ ] **Step 2: Spot-check the rendered markdown**

Run:

```bash
sed -n '/^## Install/,/^## /p' README.md | head -30
```

Expected: the new `### With Homebrew (recommended)` section appears immediately under `## Install`, followed by the unchanged `### Download a release` section.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document brew install in README

- Add brew install --cask remerle/tap/bannershift as the recommended
  install option, above the manual download
- Manual download stays for users without Homebrew"
```

---

## Task 4: Document the tap and PAT in `docs/release.md`

The release docs already cover the `release-signing` environment and its secrets. Add a parallel section covering the cask-bump workflow and the `homebrew-tap-bump` environment, including PAT scope and rotation.

**Files:**
- Modify: `docs/release.md` (append a new top-level section)

- [ ] **Step 1: Append the new section**

Append to `docs/release.md`, after the existing "Verifying a build" section (so it lands at the end of the file):

```markdown
## Homebrew distribution

BannerShift ships through a personal Homebrew tap at `remerle/homebrew-tap`.
The cask is auto-bumped by `.github/workflows/bump-cask.yml`, which fires
when a GitHub release is **published** (not on tag push).

### Release flow with the cask in play

1. Push a `v*` tag → `release.yml` signs and notarizes, creates a **draft**
   GitHub release with the `.zip`, `.dmg`, and checksum attached.
2. Open the draft in the GitHub UI, edit notes, click **Publish release**.
3. Publishing fires `bump-cask.yml`, which downloads the `.dmg` from the
   public release URL, computes its sha256, rewrites `version` and
   `sha256` in `Casks/bannershift.rb` in the tap, and pushes to the tap's
   `main`. The job requires environment approval; one click.

A prerelease (`prerelease: true` on the GitHub release) does **not** bump
the cask.

### One-time GitHub configuration

In **Settings → Environments** on this repo, create an environment named
`homebrew-tap-bump`. Add **Required reviewers** (yourself). Then add this
environment secret (scoped to `homebrew-tap-bump`, not repo-wide):

| Secret | Value | How to obtain |
|---|---|---|
| `HOMEBREW_TAP_PAT` | Fine-grained PAT, repository access = `remerle/homebrew-tap` only, permission = `Contents: Read & write`. Nothing else. | GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. |

**PAT rotation:** Fine-grained PATs have a maximum lifetime of one year.
Record the expiry the GitHub UI shows you; renew before that date and
update the `HOMEBREW_TAP_PAT` secret in the environment. A bump that fails
because the PAT expired will surface as a red workflow run; the release
artifacts are not affected.

### Manual fallback

If the auto-bump fails (PAT expired, network error, tap repo unavailable),
either rerun the workflow from the Actions tab or apply the bump manually
to the tap:

```bash
git clone git@github.com:remerle/homebrew-tap.git
cd homebrew-tap
VERSION=1.2.3
SHA256="$(curl -sL "https://github.com/remerle/BannerShift/releases/download/v${VERSION}/BannerShift-${VERSION}.dmg" | shasum -a 256 | awk '{print $1}')"
/usr/bin/sed -i.bak -E \
  -e "s|^([[:space:]]*version )\"[^\"]*\"|\\1\"${VERSION}\"|" \
  -e "s|^([[:space:]]*sha256 )\"[^\"]*\"|\\1\"${SHA256}\"|" \
  Casks/bannershift.rb
rm -f Casks/bannershift.rb.bak
git commit -am "bannershift ${VERSION}"
git push
```
```

- [ ] **Step 2: Verify the markdown renders sensibly**

Run:

```bash
grep -n '^## ' docs/release.md
```

Expected: the new `## Homebrew distribution` heading appears at the bottom of the file, after `## Verifying a build`.

- [ ] **Step 3: Commit**

```bash
git add docs/release.md
git commit -m "Document Homebrew cask-bump workflow and PAT rotation

- Add Homebrew distribution section covering the new bump-cask.yml
  workflow and the homebrew-tap-bump environment
- Document HOMEBREW_TAP_PAT scope (single repo, Contents:Write only)
  and one-year rotation expectation
- Document manual-fallback bump procedure"
```

---

## Task 5: Manual setup (outside this repo)

These steps cannot be performed by the workflow itself. Complete them before the next release tag, otherwise the bump workflow will fail when it runs.

**Note:** Nothing in this task produces a commit in the BannerShift repo. It is a checklist for the maintainer.

- [ ] **Step 1: Create the `homebrew-tap` repo**

On GitHub:

- Name: `remerle/homebrew-tap` (the `homebrew-` prefix is required by Homebrew; the suffix is free-form but the tap install command will be `remerle/tap`).
- Visibility: **Public** (required for `brew tap` over HTTPS without auth).
- Default branch: `main`.
- Initialize with a placeholder README (will be overwritten in Step 2).

- [ ] **Step 2: Seed the tap with the initial cask and README**

Clone the new tap locally, then add the two files. The cask `version` and `sha256` carry placeholder values that the next published release will overwrite; until that release ships, the cask will fail `brew audit --online` because the `.dmg` URL is not yet live — that is expected and resolves on first release.

Create `Casks/bannershift.rb`:

```ruby
cask "bannershift" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/remerle/BannerShift/releases/download/v#{version}/BannerShift-#{version}.dmg",
      verified: "github.com/remerle/BannerShift/"
  name "BannerShift"
  desc "Repositions notification banners onto a 3x3 grid"
  homepage "https://github.com/remerle/BannerShift"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "BannerShift.app"

  uninstall quit: "dev.emerle.bannershift"

  zap trash: [
    "~/Library/Caches/dev.emerle.bannershift",
    "~/Library/HTTPStorages/dev.emerle.bannershift",
    "~/Library/Logs/BannerShift.log",
    "~/Library/Preferences/dev.emerle.bannershift.plist",
    "~/Library/Saved Application State/dev.emerle.bannershift.savedState",
  ]
end
```

Create `README.md` for the tap:

```markdown
# remerle/homebrew-tap

Personal Homebrew tap for [BannerShift](https://github.com/remerle/BannerShift).

## Install

```bash
brew install --cask remerle/tap/bannershift
```

## Maintenance

The cask is auto-maintained by BannerShift's release workflow. Manual
changes will likely be overwritten by the next release. See
[BannerShift's release docs](https://github.com/remerle/BannerShift/blob/main/docs/release.md#homebrew-distribution)
for details.
```

Commit both files and push to the tap's `main` branch.

- [ ] **Step 3: Generate the fine-grained PAT**

On GitHub:

- Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token.
- Token name: `BannerShift homebrew-tap bump`.
- Resource owner: your account.
- Repository access: **Only select repositories** → choose `remerle/homebrew-tap` only.
- Repository permissions: **Contents: Read and write**. Leave everything else at "No access."
- Expiration: the maximum the UI allows (typically 1 year). Record the expiry date in `docs/release.md` after the fact, or in a calendar reminder.
- Copy the token (you will not see it again).

- [ ] **Step 4: Create the `homebrew-tap-bump` environment and add the PAT**

On the BannerShift repo, Settings → Environments → New environment:

- Name: `homebrew-tap-bump`.
- Deployment protection rules → **Required reviewers** → add yourself.
- Environment secrets → New secret:
  - Name: `HOMEBREW_TAP_PAT`.
  - Value: the PAT from Step 3.

- [ ] **Step 5: Sanity-check the cask locally**

With the tap pushed and the cask file in place, confirm the cask at least parses cleanly. Until a real release lands, the `--online` audit will fail on the URL, which is expected.

```bash
brew tap remerle/tap
brew style remerle/tap/bannershift
```

Expected:
- `brew tap` succeeds (Homebrew clones the repo locally).
- `brew style` passes (the Ruby cask DSL parses and conforms to style).
- A subsequent `brew audit --cask --online bannershift` will warn or error on the URL until a real release ships at that version — that is expected and is **not a failure of this plan**.

---

## Task 6: Final review

A quick self-check that the diff is consistent and nothing was missed.

- [ ] **Step 1: Diff summary**

Run:

```bash
git log --oneline main..HEAD
```

Expected: at least these three new commits, in this order (newest last; the branch may also carry earlier spec/plan commits depending on how it was created):

1. `Add workflow to auto-bump Homebrew cask on release.published`
2. `Document brew install in README`
3. `Document Homebrew cask-bump workflow and PAT rotation`

- [ ] **Step 2: Re-run `make validate`**

Run:

```bash
make validate
```

Expected: PASS. (None of the changes touch `Sources/` or `Tests/`, but running `validate` confirms nothing accidentally broke.)

- [ ] **Step 3: Re-lint the workflow**

Run:

```bash
actionlint .github/workflows/bump-cask.yml .github/workflows/release.yml
```

Expected: no output. Linting both workflows catches any incidental issue introduced in the new one.

- [ ] **Step 4: Confirm spec coverage**

Open the spec (`docs/superpowers/specs/2026-05-26-homebrew-cask-distribution-design.md`) side-by-side with the diff. Confirm each section in the spec is reflected in either an in-repo file or Task 5's manual setup:

- Tap repo, cask file content → Task 5.
- `bump-cask.yml` workflow → Task 2.
- README install line → Task 3.
- `docs/release.md` documentation → Task 4.
- PAT, environment, manual rotation → Task 5 + Task 4 documentation.

If anything in the spec is not covered by either a file in the diff or a Task 5 manual step, surface it before declaring the plan complete.

---

## Post-merge smoke test

Cannot be performed inside the plan; documented here so the maintainer remembers to do it on the first real release after merge.

1. Push a `v*` tag.
2. Approve the `release-signing` environment when prompted.
3. Wait for the draft release to appear in the GitHub UI; edit notes; click Publish.
4. Approve the `homebrew-tap-bump` environment when prompted.
5. Watch the `bump-cask.yml` run succeed. Open the tap repo and confirm `Casks/bannershift.rb` now has the real version and sha256.
6. On a clean Mac (or a sandbox account), run:

   ```bash
   brew tap remerle/tap          # only needed once per machine
   brew install --cask remerle/tap/bannershift
   ```

   Confirm:
   - The install completes without a Gatekeeper error.
   - `/Applications/BannerShift.app` runs and prompts for Accessibility.
7. Exercise the uninstall path:

   ```bash
   brew uninstall --cask bannershift
   brew uninstall --zap bannershift
   ```

   Confirm:
   - The `.app` is gone after `--cask` uninstall.
   - `~/Library/Logs/BannerShift.log` and `~/Library/Preferences/dev.emerle.bannershift.plist` are gone after `--zap`.

If any of those steps fail, file an issue against the cask file in the tap, not the BannerShift repo (so future cask iterations stay self-contained).
