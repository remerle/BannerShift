# Releasing

BannerShift releases are signed with a Developer ID certificate, notarized by
Apple, stapled, and packaged. There are two ways to run the pipeline: locally
from a dev machine, or via GitHub Actions on a version tag. Both produce
equivalent, notarized artifacts.

The **git tag is the version source of truth**. The committed `Resources/Info.plist`
carries a placeholder version (`1.0.0`); at release time the version is parsed
from the tag (`v1.2.3` → `1.2.3`) and written into `CFBundleShortVersionString`
and `CFBundleVersion` with `PlistBuddy`. Dev builds use the placeholder.

## Via GitHub Actions (recommended)

`.github/workflows/release.yml` runs the full pipeline on a `macos-14` runner
when you push a `v*` tag. It produces a **draft** GitHub release with a notarized
`.zip`, a notarized `.dmg`, and a SHA-256 checksum file.

```bash
git tag v1.2.3
git push origin v1.2.3
```

Then open the Actions tab, approve the `release-signing` environment when
prompted, and let the workflow sign, notarize, and create the draft release. Edit
the notes and publish from the GitHub UI.

The workflow refuses to release a tag whose commit isn't reachable from
`origin/main`, so cut releases from `main`.

### One-time GitHub configuration

In repository **Settings → Environments**, create an environment named
`release-signing` and add **Required reviewers** (yourself). This is the manual
approval gate; secrets only mount after a reviewer approves. Then add these
**environment** secrets (scoped to `release-signing`, not repo-wide):

| Secret | Value | How to obtain |
|---|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | base64 of your Developer ID Application cert exported as `.p12` | `security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P "<password>" -o cert.p12 && base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | the password you set when exporting the `.p12` | you choose it at export time |
| `DEVELOPER_ID_APPLICATION_IDENTITY` | full signing identity string | `security find-identity -v -p codesigning \| grep "Developer ID Application"` → use the quoted name, e.g. `Developer ID Application: Your Name (TEAMID12)` |
| `AC_API_KEY_BASE64` | base64 of your App Store Connect API key `.p8` | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |
| `AC_API_KEY_ID` | the 10-character key ID | App Store Connect → Users and Access → Integrations → API Keys |
| `AC_API_ISSUER_ID` | the issuer UUID | same screen as above |

### Security posture of the workflow

- The `.p12` is the highest-value secret on this repo. Compromise lets an
  attacker sign macOS malware as you until Apple revokes (a 24-48 hour window).
- All secrets are scoped to the `release-signing` environment, so a workflow
  added by a malicious PR cannot read them.
- The job creates an **ephemeral keychain** with a random password, imports the
  cert, signs, then restores the user keychain search list and deletes the
  ephemeral keychain on cleanup. No persistent state is left on the runner.
- Third-party actions are first-party only (`actions/checkout`, `actions/cache`,
  `actions/upload-artifact`, `actions/download-artifact`). No marketplace actions
  touch the signing path.

## Locally (via 1Password)

The local path pulls signing material out of 1Password and runs the same sign +
notarize + staple + package steps.

```bash
make secrets-setup   # first time on a machine: import Developer ID cert, then pull secrets
make secrets         # subsequent runs: refresh .env + .secrets/ from 1Password
make release         # build, sign, notarize, staple, package
```

(`make secrets-setup` / `make secrets` wrap `./scripts/populate-secrets.sh --import-certs`
/ `./scripts/populate-secrets.sh`; `make release` wraps `./scripts/release.sh`. The
local path is a manual break-glass option — GitHub Actions above is the primary
way to cut a release.)

### Prerequisites

1. A 1Password vault with an item for the App Store Connect API key holding:
   - the `.p8` file as an attachment (e.g. `AuthKey_XXXXXXXXXX.p8`);
   - `key id` (text) — the 10-character key ID;
   - `issuer id` (text) — the issuer UUID;
   - `key filename` (text) — the exact filename of the attached `.p8`. This is
     read at runtime so the key ID never appears in the script.
2. A 1Password item for the Developer ID Application certificate (and one for the
   Installer cert if you later add a `.pkg` build).
3. Edit `scripts/populate-secrets.sh` and replace the placeholders: `VAULT`,
   `APP_CERT_ITEM`, `INSTALLER_CERT_ITEM`, `ASC_ITEM`.
4. Run `op signin` if you aren't already signed in to the 1Password CLI.

### What the scripts do

`scripts/populate-secrets.sh` writes a gitignored `.env` and `.secrets/AuthKey.p8` (mode
`0600`). With `--import-certs` it also fetches the `.p12` files, imports them into
the login keychain scoped to `codesign`/`security`/`productsign` (not `-A`), and
deletes the `.p12` files afterward. It sets `umask 077` and traps cleanup on
exit, so secret material doesn't linger if the script aborts.

`scripts/release.sh` consumes `.env` and `.secrets/`, builds the universal app, signs it
with the Developer ID identity, notarizes via `xcrun notarytool submit --wait`
(failing fast on any non-`Accepted` status and fetching the notary log for
diagnostics), staples the ticket, validates, runs a `spctl` smoke check, and
packages `build/BannerShift-<version>.tar.gz`. It traps cleanup so the
intermediate notarization ZIP is removed even on an interrupted or rejected run.

## Verifying a build

```bash
spctl --assess --type execute -vv build/BannerShift.app   # Gatekeeper assessment
xcrun stapler validate build/BannerShift.app              # notarization ticket present
codesign --verify --deep --strict --verbose=2 build/BannerShift.app
```
