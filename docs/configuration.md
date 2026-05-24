# Configuration & data

BannerShift stores its settings in `UserDefaults` and its rules in the same
defaults domain, writes a single log file, and reads nothing else from disk. This
document lists every setting, where it lives, and the values it accepts. Most
people never need this — everything here is also reachable from the menu-bar UI.

The defaults domain (and bundle identifier) is **`com.emerle.BannerShift`**.

## Preferences

| Setting | `UserDefaults` key | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| Default position | `selectedPosition` | String | `top-middle` | Where banners go when no rule overrides. One of the [position values](#position-values). |
| Menu-bar icon hidden | `iconHidden` | Bool | `false` | Hides the menu-bar icon. Reset to `false` automatically when you bring the app to the foreground, so it's recoverable. |
| Debug logging | `debugLoggingEnabled` | Bool | `false` | Enables verbose, content-bearing logging. See [Logging](#logging). |

Preferences are read live from `UserDefaults` on each access, so changing one
takes effect on the next reposition pass without a restart. An unrecognized
`selectedPosition` value falls back to `top-middle`.

You can set these from the command line if needed:

```bash
defaults write com.emerle.BannerShift selectedPosition -string "bottom-right"
defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES
```

## Rules

Rules are stored as a JSON array under the `rules` key in the same
`com.emerle.BannerShift` defaults domain (not a standalone file). Edit them
through **Rules…** in the menu bar rather than by hand.

Each rule is:

| Field | Type | Required | Meaning |
| --- | --- | --- | --- |
| `id` | String | yes | Stable UUID, generated on creation, never mutated. |
| `name` | String | yes | A label for your reference; not used for matching. |
| `enabled` | Bool | yes | When `false`, the matcher skips the rule. |
| `appPattern` | String | no | Regex matched against the source app's display name. |
| `bundleIDPattern` | String | no | Regex matched against the resolved bundle identifier. |
| `titlePattern` | String | no | Regex matched against the banner title. |
| `subtitlePattern` | String | no | Regex matched against the banner subtitle. |
| `bodyPattern` | String | no | Regex matched against the banner body. |
| `position` | String | no | Position override; omit to use the global default. |
| `animation` | String | no | Animation override; omit for `none`. |

Matching semantics:

- Patterns are Swift `Regex`, compiled **case-insensitively** with
  dot-matches-newlines. A rule with multiple pattern fields matches only when
  **all** of them match (logical AND). An omitted or empty pattern matches
  anything.
- Rules are evaluated in order; the **first enabled rule that matches wins**, and
  its `position`/`animation` override the defaults.
- A rule with an **invalid regex fails closed**: it's skipped and the error is
  logged, never crashing the matcher.
- If the stored rules JSON is **corrupt**, BannerShift logs the failure and starts
  with an empty rule set rather than refusing to launch.

## Position values

The nine grid positions and the strings stored for them:

| Stored value | Menu label |
| --- | --- |
| `top-left` | Top Left |
| `top-middle` | Top Middle |
| `top-right` | Top Right |
| `middle-left` | Middle Left |
| `middle` | Middle |
| `middle-right` | Middle Right |
| `bottom-left` | Bottom Left |
| `bottom-middle` | Bottom Middle |
| `bottom-right` | Bottom Right |

Middle and bottom positions are padded `30 pt` clear of the Dock.

## Animation values

| Stored value | Menu label | Behavior |
| --- | --- | --- |
| `none` | None | Snap straight to the target position. |
| `slide` | Slide | Slide from the original spot to the target (~0.2 s). |
| `shake` | Shake | Snap to target, then oscillate horizontally (~0.25 s). |
| `bounce` | Bounce | Snap to target, then oscillate vertically (~0.25 s). |

Animations start after a short delay (~0.15 s) so they don't fight the OS's own
banner entry animation, and run at 60 fps from a precomputed frame schedule.

## Launch at login

Managed through **Launch at Login** in the menu bar, backed by
`SMAppService.mainApp` (the modern Service Management API). The toggle reflects
four states:

- **not registered** — won't launch at login;
- **enabled** — registered and will launch at login;
- **requires approval** — registered, but you must approve it in
  System Settings → General → Login Items (the menu can open this for you);
- **error** — the Service Management call failed.

## Logging

BannerShift writes one log file:

```
~/Library/Logs/BannerShift.log
```

- Created with mode `0600` (owner read/write only), re-asserted on each launch.
- Three levels: `INFO` (routine events — launch, AX activity, rule load count),
  `ERROR` (recoverable failures), and `DEBUG`.
- **`DEBUG` is the only level that records notification content**, and it's
  gated on the `debugLoggingEnabled` preference, evaluated at write time. With
  debug logging off (the default), **no notification text is written to disk.**
- The file is capped at 5 MB; if it exceeds that at launch, it's removed and
  recreated (no rolling history).
- `INFO` and `ERROR` lines (which never contain notification content) are also
  mirrored to the macOS unified log, so the agent shows up in Console.app and
  `sysdiagnose` like any other app. `DEBUG` is **never** mirrored — notification
  content stays in the gated file only. View the unified-log stream with:

  ```bash
  log stream --predicate 'subsystem == "com.emerle.BannerShift"' --level info
  ```

The file is the system of record; the unified-log mirror is a convenience and a
fallback for when a file write fails.

Tail it during development with:

```bash
make tail-log
```

Turn debug logging on only while diagnosing something, and off again afterward,
since it writes the content of your notifications to disk.

## Accessibility permission

BannerShift requires Accessibility permission and **terminates if it's denied** —
it has no degraded mode. On first launch it calls
`AXIsProcessTrustedWithOptions` with the system prompt enabled, which directs you
to System Settings → Privacy & Security → Accessibility. Grant it there and
relaunch. See the [security model](../SECURITY.md#security-model) for what that
access is and isn't used for.
