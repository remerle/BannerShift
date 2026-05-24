# Security Policy

## Supported versions

BannerShift is a single-track project; only the latest released version receives
security fixes. There are no long-term-support branches.

| Version | Supported |
| ------- | --------- |
| Latest release (`1.x`) | Yes |
| Older releases | No |

## Reporting a vulnerability

Please report security issues **privately**, not as a public GitHub issue.

Use GitHub's private vulnerability reporting:
[**Report a vulnerability**](https://github.com/remerle/BannerShift/security/advisories/new).

Include the macOS version, BannerShift version, reproduction steps, and the
impact you observed. You'll get an acknowledgement as soon as the report is
triaged. This is a personal project, so there is no guaranteed response SLA, but
credible reports are taken seriously and will be addressed before public
disclosure where practical.

## Security model

Understanding what BannerShift can and cannot touch is the fastest way to reason
about its risk surface.

- **Accessibility access.** BannerShift requires macOS Accessibility permission.
  This is a powerful entitlement: it lets the app read the on-screen
  accessibility tree of the notification UI process and move its windows. The app
  reads notification text (app name, title, subtitle, body) **only** to evaluate
  your matching rules, and it holds that text in memory only.
- **No content on disk by default.** Notification content is never written to
  disk unless you explicitly turn on debug logging (off by default). See
  [docs/configuration.md](docs/configuration.md#logging). The default log level
  records operational events, not notification bodies.
- **No network, no telemetry.** BannerShift makes no network connections and
  collects no analytics. It is a single local process serving a single user.
- **No process injection or rendering.** It does not subclass, inject into, or
  load code into other processes, and it does not render its own banners. It
  only reads the accessibility tree and repositions existing windows.
- **Minimal entitlements.** The bundle ships the smallest entitlement set that
  works (`Resources/BannerShift.entitlements`). New entitlements require a
  documented justification in the PR that introduces them.
- **Fail-closed on permission.** If Accessibility permission is denied, the app
  terminates rather than running in a degraded mode.
- **Signed and notarized.** Released builds are signed with a Developer ID
  certificate and notarized by Apple. See [docs/release.md](docs/release.md).

## Reporting non-security bugs

For ordinary bugs and feature requests, use the public
[issue tracker](https://github.com/remerle/BannerShift/issues).
