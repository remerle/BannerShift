# Contributing to BannerShift

Thanks for your interest. BannerShift is primarily a personal project, but
well-scoped issues and pull requests are welcome. There's no guaranteed response
time, so for anything non-trivial it's worth opening an issue to discuss the
approach before you invest in a large change.

For the deeper picture of how the code is laid out, read
[DEVELOPERS.md](DEVELOPERS.md) and the documents under [`docs/`](docs/).

## Ground rules

- **Stay in scope.** One logical change per PR. Avoid drive-by refactors of code
  you weren't asked to touch.
- **Keep the Core/executable split intact.** Pure, testable logic lives in
  `Sources/BannerShiftCore/` and must not import `AppKit`, `ApplicationServices`,
  or `Cocoa`. System integration lives in `Sources/BannerShift/`. See
  [docs/architecture.md](docs/architecture.md).
- **No new entitlements** without a documented reason in the PR description.
- **Notification content is sensitive.** Don't add code paths that write
  notification text to disk outside of explicit debug logging.

## Development setup

You need macOS 13+ and a Swift 6.0+ toolchain (Xcode 16+ or the matching
toolchain); the test suite relies on the Swift Testing framework bundled with
Swift 6. Then:

```bash
git clone https://github.com/remerle/BannerShift.git
cd BannerShift
make build
make test
```

The full command reference is in [DEVELOPERS.md](DEVELOPERS.md#commands).

## Before you open a pull request

Run the pre-merge gate and make sure it's green:

```bash
make validate   # swift-format + SwiftLint, build, and test
```

Periodically (not on every change) also run the slower analyzer pass to catch
dead code and unused imports:

```bash
make analyze
```

Checklist:

- [ ] `make validate` passes.
- [ ] New or changed behavior in `BannerShiftCore` has tests
      (`Tests/BannerShiftCoreTests/`, Swift Testing). Executable-target changes
      are verified manually against real notifications.
- [ ] User-visible changes are noted in the `Unreleased` section of
      [CHANGELOG.md](CHANGELOG.md).
- [ ] Lint findings are fixed, not suppressed. If a suppression is truly
      warranted, scope it to one line with a `// Reason:` comment and call it out
      in the PR description.

## Commit and PR conventions

- Commit messages: a short imperative title, a blank line, then a bulleted list
  of the logical changes.
- Keep documentation-only commits separate from behavior changes.
- In the PR description, explain *why*, not just *what*, and flag anything that
  touches the undocumented macOS internals listed in
  [docs/architecture.md](docs/architecture.md#os-fragility).

## Testing philosophy

Cover the math and logic exhaustively (coordinate transforms, animation frames,
rule matching); cover orchestration loosely. Don't mock `BannerShiftCore` types
— they're already pure value types. Tests must not depend on the host machine's
display configuration or current preferences. See
[DEVELOPERS.md](DEVELOPERS.md#testing) for details.
