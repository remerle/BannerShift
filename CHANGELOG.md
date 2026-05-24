# Changelog

All notable changes to BannerShift are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are cut by pushing a `vX.Y.Z` git tag; the tag is the version source of
truth and is injected into the app bundle at build time. See
[docs/release.md](docs/release.md).

## [Unreleased]

### Changed

- When a test notification can't be sent because notifications are disabled, the
  alert now offers an "Open Settings" button that jumps to the Notifications
  pane in System Settings.

### Fixed

- Banners now reposition correctly on macOS 26, whose rebuilt Notification
  Center previously left every banner in the top-right regardless of the chosen
  position. The banner also no longer flickers between positions as it appears.
- Dismissing a banner no longer flashes it back in the top-right corner as it
  slides away.

## [1.0.0] - 2026-05-24

### Added

- Reposition every native macOS notification banner onto one of nine positions
  in a 3x3 grid (corners, edge midpoints, screen center).
- Per-notification rules matching on app name, bundle ID, title, subtitle, or
  body via case-insensitive Swift `Regex`. Each rule can override the global
  position and choose an animation (`none`, `slide`, `shake`, `bounce`).
- Menu-bar UI: position picker, rules editor with a live sample-text tester,
  test-notification sender, three-state launch-at-login toggle, hide-icon
  action, and an about window.
- Runs as a background agent (`LSUIElement`) with no Dock icon and no main
  window.
- Multi-display aware: banners are repositioned on the screen they belong to.
- Optional on-disk debug logging (off by default; never writes notification
  content to disk unless explicitly enabled).
- Signed and notarized release pipeline, runnable locally or via GitHub Actions
  on a version tag.

[Unreleased]: https://github.com/remerle/BannerShift/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/remerle/BannerShift/releases/tag/v1.0.0
