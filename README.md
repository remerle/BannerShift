# BannerShift

A macOS background utility that repositions native notification banners to a user-chosen location on the screen.

The system normally posts every banner at the top-right corner. BannerShift lets you pick any of nine positions arranged in a 3x3 grid and ensures every banner the OS posts is repositioned there for as long as the banner is visible. It does not render its own banners, does not subclass or inject anything into other processes, and reads no notification content except to evaluate user-defined matching rules (and even then, only in memory; never to disk unless you turn on debug logging).

## What it does

- Repositions every notification banner to one of nine grid cells: corners, edge midpoints, or screen center.
- Optional per-notification rules: match by app name, bundle ID, title, subtitle, or body (Swift `Regex`, case-insensitive). Each rule can override the global position and pick an animation style (`none`, `slide`, `shake`, `bounce`).
- Runs as a per-user background agent (`LSUIElement=true`). No Dock icon, no main window. Optional menu-bar icon for the position picker, rules editor, test notification, launch-at-login toggle, and about/quit.
- Single process, single user, no network, no telemetry. Requires only Accessibility permission.

For the full functional specification, see [`plan.md`](plan.md). For the task-by-task implementation plan, see [`docs/superpowers/plans/2026-05-22-banner-shift.md`](docs/superpowers/plans/2026-05-22-banner-shift.md).

## Install (dev build)

Until a notarized release is published, build locally:

```bash
make build         # incremental SwiftPM build
./scripts/build-dev.sh   # universal (arm64 + x86_64), ad-hoc signed, packaged as build/BannerShift.app
open build/BannerShift.app
```

On first launch, macOS will prompt for Accessibility permission. Grant it in System Settings, then relaunch BannerShift. (The app intentionally terminates on a denied permission rather than running in a degraded mode; see plan §4.)

## Use

Click the bell icon in the menu bar:

- **Rules...** opens the rule editor (table of rules + per-rule detail pane + sample-text tester).
- **Default Position** lists the nine positions; the current one is checked. Pick a different one to take effect immediately.
- **Send a Test Notification** posts a real banner so you can confirm placement.
- **Launch at Login** is a three-state toggle: not registered, enabled, requires approval.
- **Hide Menu Bar Icon...** removes the icon (the app keeps running). Relaunch BannerShift to bring it back.
- **About BannerShift** shows the version and copyright.

## Develop

```bash
make help         # list every target
make build        # debug build
make test         # 75 tests, Swift Testing
make format       # apply swift-format
make format-check # report only, no rewrites
make validate     # format-check + build + test (CI gate)
make dev          # run scripts/build-dev.sh
make run          # build + open the .app
make clean        # remove .build and build
make tail-log     # tail ~/Library/Logs/BannerShift.log
```

The project is split between two SwiftPM targets:

- `BannerShiftCore` (library, in `Sources/BannerShiftCore/`): pure value types and pure logic. Fully unit-tested, no system-API dependencies.
- `BannerShift` (executable, in `Sources/BannerShift/`): AppKit + Accessibility integration. Verified via the manual smoke pass in plan §22 / impl-plan Task 26.

Tests live under `Tests/BannerShiftCoreTests/` using Swift Testing (`@Test`, `#expect`). Run with `make test`.

## Release (signed + notarized)

Two paths: drive the pipeline locally from your dev machine, or push a tag and let GitHub Actions do the work.

### Locally (via 1Password)

```bash
./populate-secrets.sh --import-certs   # first time on this machine
./populate-secrets.sh                  # subsequent runs
./release.sh
```

Prerequisites:

1. A 1Password vault containing an item for the App Store Connect API key with these fields:
   - the `.p8` file as an attachment (e.g. `AuthKey_XXXXXXXXXX.p8`)
   - `key id` (text) → the 10-character key ID from App Store Connect → Users and Access → Integrations → API Keys
   - `issuer id` (text) → the issuer UUID from the same screen
   - `key filename` (text) → the exact filename of the attached `.p8` (e.g. `AuthKey_XXXXXXXXXX.p8`). This is read at runtime so the key ID never appears in the script.
2. A 1Password item for the Developer ID Application certificate (and one for the Installer cert if needed for `--import-certs`).
3. Edit `populate-secrets.sh` and replace the placeholders with your values:
   - `VAULT` → your 1Password vault ID.
   - `APP_CERT_ITEM` → your 1Password item ID for the Developer ID Application cert.
   - `INSTALLER_CERT_ITEM` → your 1Password item ID for the Developer ID Installer cert.
   - `ASC_ITEM` → your 1Password item ID for the App Store Connect API key.
4. Run `op signin` if you are not already signed in to the 1Password CLI.

`populate-secrets.sh` writes a gitignored `.env` and `.secrets/AuthKey.p8` (mode 0600). `release.sh` consumes them, builds, signs with the Developer ID identity, notarizes via `xcrun notarytool`, staples, and packages as `build/BannerShift-<version>.tar.gz`.

### Via GitHub Actions

`.github/workflows/release.yml` runs the same pipeline on a `macos-14` runner when you push a version tag. Output is a draft GitHub release with both a notarized `.zip` and a notarized `.dmg`, plus a SHA-256 checksum file.

**How to release:**

```bash
git tag v1.2.3
git push origin v1.2.3
```

Then visit the Actions tab, approve the `release-signing` environment when prompted, and the workflow signs, notarizes, and creates a draft release. Edit the notes and publish from the GitHub UI.

**One-time GitHub configuration (`Settings`):**

1. Create environment `release-signing` (`Settings > Environments > New environment`).
2. Add **Required reviewers** (yourself). This is the manual approval gate. Secrets only mount after a reviewer approves.
3. Add the following **environment secrets** (scoped to `release-signing`, not repo-wide):

| Secret | Value | How to obtain |
|---|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | base64 of your Developer ID Application cert exported as `.p12` | `security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P "<password>" -o cert.p12 && base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | the password you set when exporting the `.p12` | (you choose it at export time) |
| `DEVELOPER_ID_APPLICATION_IDENTITY` | full signing identity string | `security find-identity -v -p codesigning \| grep "Developer ID Application"` → use the quoted name, e.g. `Developer ID Application: Your Name (TEAMID12)` |
| `AC_API_KEY_BASE64` | base64 of your App Store Connect API key `.p8` | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |
| `AC_API_KEY_ID` | the 10-character key ID | App Store Connect → Users and Access → Integrations → API Keys |
| `AC_API_ISSUER_ID` | the issuer UUID | same screen as above (top of the page) |

**Security posture:**

- The `.p12` is the highest-value secret you will ever set on this repo. Compromise lets an attacker sign macOS malware as you until Apple revokes (24-48 hour window).
- All secrets are scoped to the `release-signing` environment, not repo-wide. A workflow file added by a malicious PR cannot read them.
- The workflow creates an ephemeral keychain with a random password, imports the cert, then deletes the keychain on cleanup. No persistent state on the runner.
- Third-party actions are first-party only (`actions/checkout`, `actions/cache`, `actions/upload-artifact`, `actions/download-artifact`). Zero marketplace actions in the signing path.
- The version is sourced from the git tag (`refs/tags/v1.2.3`) and injected into `Info.plist` at build time; no version string in the repo to keep in sync.

## Project layout

```
.
├── Makefile                      # build/test/format/validate driver (workbench-platform pattern)
├── Package.swift                 # SwiftPM manifest (macOS 13+, swift-testing dep)
├── plan.md                       # functional specification (23 sections)
├── populate-secrets.sh           # 1Password -> .env materializer
├── release.sh                    # Developer ID sign + notarize + staple + package
├── Resources/
│   ├── Info.plist                # LSUIElement, AX usage description, bundle metadata
│   └── BannerShift.entitlements
├── Sources/
│   ├── BannerShiftCore/          # pure logic + value types (unit-tested)
│   └── BannerShift/              # AppKit + AX integration (executable)
├── Tests/BannerShiftCoreTests/   # Swift Testing, 75 tests
├── docs/superpowers/plans/       # task-by-task implementation plan
└── scripts/
    └── build-dev.sh              # universal binary, ad-hoc signed
```

## Constraints and known fragilities

BannerShift depends on a small number of undocumented macOS behaviors (banner accessibility subroles, the Notification Center panel identifier, the full-screen container window invariant). When Apple changes any of these across a major macOS release, the corresponding constants in `Sources/BannerShiftCore/Constants.swift` need updating. See plan.md §20 for the full list.

## License

Copyright 2026 Ryan Emerle. All rights reserved.
