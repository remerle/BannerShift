# Developing BannerShift

This is the entry point for working on BannerShift. It covers prerequisites, the
build/test/lint workflow, and how the project is laid out. For the deeper detail
it links into [`docs/`](docs/).

- [docs/architecture.md](docs/architecture.md) — how it works internally and the
  banner repositioning data flow.
- [docs/configuration.md](docs/configuration.md) — every setting, where it's
  stored, and the values it accepts.
- [docs/release.md](docs/release.md) — the signing/notarization release pipeline.
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution ground rules and PR checklist.

## Prerequisites

- macOS 13 (Ventura) or newer.
- A Swift 5.10 toolchain — Xcode 15+ or the matching standalone toolchain.
- [SwiftLint](https://github.com/realm/SwiftLint) and Apple's
  [swift-format](https://github.com/swiftlang/swift-format) on your `PATH` for
  `make lint` / `make format`.

Clone and confirm the suite is green:

```bash
git clone https://github.com/remerle/BannerShift.git
cd BannerShift
make validate
```

## Commands

The `Makefile` is the dev driver; `make help` lists every target.

| Command | What it does |
| --- | --- |
| `make build` | Debug build (`swift build`). |
| `make test` | Run the Swift Testing suite over `BannerShiftCore`. |
| `make format` | Apply swift-format in place. |
| `make lint` | swift-format check + SwiftLint, no rewrites. Fails on drift. |
| `make format-check` | Alias for `make lint`. |
| `make analyze` | Slower SwiftLint analyzer rules (unused declarations/imports). Run periodically; not part of `validate`. |
| `make validate` | **Pre-merge gate:** lint + build + test. |
| `make dev` | Universal, ad-hoc-signed `.app` at `build/BannerShift.app`. |
| `make run` | `make dev`, then open the app. |
| `make clean` | Remove `.build` and `build`. |
| `make tail-log` | Tail `~/Library/Logs/BannerShift.log`. |
| `make secrets-setup` | First-time machine setup: import Developer ID cert and pull signing secrets. |
| `make secrets` | Pull signing secrets from 1Password into `.env` + `.secrets/`. |
| `make release` | Signed, notarized, stapled release build (needs `make secrets` first). |

Always run `make validate` before declaring work complete on anything that
touches `Sources/` or `Tests/`. The signing targets (`secrets*`, `release`) are
only needed for cutting a release — see [docs/release.md](docs/release.md).

## Project layout

```
.
├── Makefile                      # build/test/format/validate driver
├── Package.swift                 # SwiftPM manifest (macOS 13+, swift-testing dep)
├── populate-secrets.sh           # 1Password -> .env + .secrets/ materializer
├── release.sh                    # Developer ID sign + notarize + staple + package
├── Resources/
│   ├── Info.plist                # LSUIElement, AX usage description, bundle metadata
│   ├── BannerShift.entitlements
│   └── AppIcon.{icns,png}
├── Sources/
│   ├── BannerShiftCore/          # pure logic + value types (unit-tested)
│   └── BannerShift/              # AppKit + AX integration (executable)
├── Tests/BannerShiftCoreTests/   # Swift Testing
├── scripts/build-dev.sh          # universal binary, ad-hoc signed
├── docs/                         # architecture, configuration, release
└── .github/workflows/release.yml # tag-triggered, environment-gated release
```

The package defines two targets — the `BannerShiftCore` library and the
`BannerShift` executable that depends on it. Why the split is non-negotiable, and
how the pieces fit together at runtime, is in
[docs/architecture.md](docs/architecture.md).

## Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest,
and live in `Tests/BannerShiftCoreTests/`. Only the Core target is unit-tested;
the executable target is verified manually against real macOS notifications on a
built `.app` (`make run`).

Guidelines:

- Cover the math and logic exhaustively (coordinate transforms, animation
  frames, rule matching, persistence). Cover orchestration loosely.
- Tests must not depend on the host machine's display configuration or current
  preferences — construct `ScreenInfo` literals in the test file.
- Don't mock `BannerShiftCore` types; they're already pure value types, so a mock
  would only test the mock framework.

## Conventions

Swift style, the documentation-comment bar, and the lint policy are spelled out
in [`CLAUDE.md`](CLAUDE.md) at the repo root. The short version: small,
deliberate `public` surface; value types over classes; `Constants.swift` is the
single source of truth for OS-dependent magic strings and numbers; fix lint
findings rather than suppress them.
