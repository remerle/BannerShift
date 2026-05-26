# BannerShift

**Move macOS notification banners wherever you want them.**

[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

macOS always drops notification banners in the top-right corner. BannerShift
quietly repositions every banner to a spot **you** choose — any of nine positions
on a 3x3 grid — and keeps it there for as long as it's on screen. It runs in the
background with no Dock icon, just a small menu-bar control.

## Features

- **Pick where banners appear** — corners, edge midpoints, or dead center.
- **Per-app and per-notification rules** — send Slack to the bottom-left, calendar
  alerts to the top-middle, and so on. Match on app name, title, subtitle, or body.
- **Optional entrance animations** — none, shake, or bounce, set globally
  or per rule.
- **Pin important notifications** — a rule can also copy matching notifications
  into an always-on-top list that stays put after the banner disappears, so the
  ones that matter don't scroll away while you're heads-down.
- **Multi-display aware** — each banner is moved on the screen it belongs to.
- **Stays out of your way** — no Dock icon, no window, no network, no telemetry.
  Just a menu-bar bell you can even hide.

## Requirements

- macOS 13 (Ventura) or newer.
- **Accessibility permission**, which macOS will prompt for on first launch.
  BannerShift needs it to see and move banner windows; it won't run without it.

## Install

### Download a release

Grab the latest notarized build from the
[**Releases**](https://github.com/remerle/BannerShift/releases) page, unzip or
mount it, and drag **BannerShift** to your Applications folder.

### Or build it yourself

If there's no release for your needs, you can build from source with a Swift
toolchain:

```bash
git clone https://github.com/remerle/BannerShift.git
cd BannerShift
make run     # builds a universal app and launches it
```

See [DEVELOPERS.md](DEVELOPERS.md) for the full toolchain setup.

## First launch

When you open BannerShift the first time, macOS will ask for **Accessibility**
permission. Grant it in **System Settings → Privacy & Security → Accessibility**,
then relaunch BannerShift. If you decline, the app closes — it has no half-working
mode without that permission.

A bell icon then appears in your menu bar. That's the whole interface.

## Using BannerShift

Click the bell icon in the menu bar:

- **Rules…** — opens the rules editor. Add a rule, give it a name, and set one or
  more patterns to match on app name, bundle identifier, title, subtitle, or
  body. The **Choose…** buttons next to App and Bundle ID let you pick an
  installed app instead of typing its name. Each rule can send matching banners
  to its own position with its own animation, and can optionally **pin** them to
  the always-on-top list (see [Pinned notifications](docs/pinned-notifications.md)).
  Patterns are wildcards, not regular expressions — see Troubleshooting below.
  The **Test…** button in the rule list checks sample banner text against the
  whole rule set and shows which rule matches first. Drag rows to reorder them:
  rules are checked top to bottom and the first match wins, so order is
  significant.
- **Default Position** — lists the nine positions with the current one checked.
  Pick another and it applies to the next banner immediately.
- **Send a Test Notification** — posts a real banner so you can confirm placement.
- **Launch at Login** — toggles whether BannerShift starts automatically. If macOS
  needs you to approve it, the menu will say so and can open the right Settings
  pane.
- **Hide Menu Bar Icon…** — removes the bell (the app keeps running). Relaunch
  BannerShift to bring it back.
- **About BannerShift** — shows the version.
- **Quit BannerShift** — stops the app (Cmd-Q).

For the exact position names, animation styles, and where settings are stored,
see [docs/configuration.md](docs/configuration.md). The always-on-top pinned list
has its own page: [docs/pinned-notifications.md](docs/pinned-notifications.md).

## Privacy & security

BannerShift reads notification text (app, title, subtitle, body) **only** to
evaluate your rules, and only in memory. It writes **no** notification content to
disk unless you explicitly turn on debug logging (off by default), makes **no**
network connections, and injects nothing into other apps. Released builds are
signed and notarized by Apple. Full details are in [SECURITY.md](SECURITY.md).

## Troubleshooting

- **Banners aren't moving.** Confirm Accessibility permission is granted in
  System Settings → Privacy & Security → Accessibility, and that BannerShift is
  running (look for the menu-bar bell). Toggling the permission off and on, then
  relaunching, clears most issues.
- **A rule isn't matching.** Open **Rules…** and use the sample-text tester.
  Patterns are **wildcards, not regular expressions**: `*` matches any run of
  characters and everything else is matched literally, case-insensitively, as a
  substring (so `Slack` matches "Slack call from Dana"). Regex syntax like
  `^Slack$` or `[A-Z]` won't work the way you expect. A rule matches only when
  *all* its filled-in fields match, and a rule with **every field left blank
  matches nothing** — there's no catch-all by omission.
- **After a macOS upgrade, nothing works.** BannerShift relies on a few
  undocumented macOS internals that Apple occasionally changes between major
  releases. Please [open an issue](https://github.com/remerle/BannerShift/issues)
  with your macOS version.

To capture a diagnostic log, turn on debug logging with
`defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES`, reproduce
the problem, then set it back to `NO` — it's the only mode that records
notification content. Details and the log location are in
[docs/configuration.md](docs/configuration.md#logging).

## Contributing & development

Issues and pull requests are welcome — it's a personal project, so responses
aren't on a schedule, but well-scoped contributions are appreciated. Start with
[CONTRIBUTING.md](CONTRIBUTING.md) and [DEVELOPERS.md](DEVELOPERS.md).

## License

[MIT](LICENSE) © 2026 Ryan Emerle.
