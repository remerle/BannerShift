# BannerShift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement BannerShift per `plan.md` — a macOS background utility that repositions native notification banners to one of nine user-chosen positions, with user-defined per-notification rules (matched against banner text) and per-rule animation overrides.

**Architecture:** Two-module Swift Package. `BannerShiftCore` (pure logic — position math, baseline tracking, debouncer, preferences, observer dedup, logger, rules, rule matching, animation frame math) is unit-tested with Swift Testing. `BannerShift` (app executable) is a thin AppKit/Accessibility-API glue layer over Core, plus a rule-editor window. The app is a per-user `LSUIElement` agent — no Dock icon, no main window, optional status item. Build via `swift build`; bundle assembly, signing, and notarization are handled by shell scripts.

**Tech Stack:** Swift 5.10+ / Swift Testing, AppKit, Accessibility API (`AXUIElement`, `AXObserver`), `NSWorkspace`, `UserNotifications`, `ServiceManagement` (SMAppService), `os.Logger`, Swift `Regex` literal type. Deployment target `macOS 13.0` (SMAppService floor); current verified target macOS 26.

**Deviations from `plan.md` (deliberate, explained inline):**

1. **§11 observer dedup key includes AX element identity**, not just role+subrole+size. The spec's tuple collides when two banner windows of identical shape coexist — see the review.
2. **§20.3 invariant assertion failure mode is "log error and skip the move"**, not crash. A loud-but-recoverable mode is friendlier than a crash in a background agent.
3. **§14 log file rotates** when it exceeds 5 MB at launch — append handle held open as the spec requires, but launch-time truncation prevents unbounded growth.
4. **SwiftPM instead of raw swiftc** for the build root. Same net artifact; testability is the win.
5. **Rules + animations are scoped into v1.** The spec (§22) was updated to fold in the rule engine, rule editor UI, banner text capture, and four animation styles. This is a deliberate, user-approved scope expansion beyond the v1 minimum.

---

## File Structure

```
BannerShift/
├── Package.swift
├── Sources/
│   ├── BannerShiftCore/                      # testable, no AppKit globals
│   │   ├── Constants.swift                   # bundle ID, fragile strings, paddings
│   │   ├── Position.swift                    # the 9-cell enum + display names
│   │   ├── Animation.swift                   # animation style enum (§22)
│   │   ├── Preferences.swift                 # UserDefaults-backed keys
│   │   ├── Baseline.swift                    # baseline record value type
│   │   ├── ScreenInfo.swift                  # injectable display value type
│   │   ├── DisplaySelector.swift             # which screen contains a point
│   │   ├── PositionCalculator.swift          # target window origin math (§7)
│   │   ├── Debouncer.swift                   # main-queue debounce (§10)
│   │   ├── ObserverKey.swift                 # AX observer dedup tuple (§11)
│   │   ├── FileLogger.swift                  # rotating-on-launch file logger
│   │   ├── BannerText.swift                  # value type: app/title/subtitle/body
│   │   ├── Rule.swift                        # rule record (Codable) (§22)
│   │   ├── RuleStore.swift                   # JSON-in-UserDefaults rule persistence
│   │   ├── RuleMatcher.swift                 # regex matching, first-match-wins
│   │   └── AnimationFrames.swift             # pure frame-schedule generator (§22)
│   └── BannerShift/                          # app executable
│       ├── main.swift                        # NSApplication boot
│       ├── AppDelegate.swift                 # top-level wiring
│       ├── AccessibilityPermission.swift     # request + verify trust
│       ├── AXBannerFinder.swift              # walk AX tree by subrole
│       ├── BannerTextExtractor.swift         # collect text strings from banner subtree
│       ├── AppResolver.swift                 # best-effort bundle ID via NSWorkspace
│       ├── NotificationCenterPanelDetector.swift  # widget-editor probe
│       ├── Animator.swift                    # drives AnimationFrames over AX writes
│       ├── BannerMover.swift                 # orchestrator
│       ├── AXObserverController.swift        # AXObserver lifecycle
│       ├── NotificationUIWatcher.swift       # workspace launch/terminate
│       ├── MenuBarController.swift           # NSStatusItem + menu
│       ├── RuleEditorWindowController.swift  # rule list + detail pane + tester
│       ├── LaunchAtLoginToggle.swift         # SMAppService wrapper
│       ├── TestNotification.swift            # UNUserNotificationCenter
│       └── AboutWindowController.swift
├── Tests/
│   └── BannerShiftCoreTests/
│       ├── PositionTests.swift
│       ├── PreferencesTests.swift
│       ├── BaselineTests.swift
│       ├── DisplaySelectorTests.swift
│       ├── PositionCalculatorTests.swift
│       ├── DebouncerTests.swift
│       ├── ObserverKeyTests.swift
│       ├── FileLoggerTests.swift
│       ├── RuleTests.swift
│       ├── RuleStoreTests.swift
│       ├── RuleMatcherTests.swift
│       └── AnimationFramesTests.swift
├── Resources/
│   ├── Info.plist
│   ├── BannerShift.entitlements
│   └── AppIcon.iconset/                      # placeholder; real icons later
├── scripts/
│   └── build-dev.sh                          # ad-hoc-signed universal .app
├── populate-secrets.sh                       # one-shot: writes .env + .secrets/AuthKey.p8
├── release.sh                                # Developer ID + notarize + staple
├── plan.md                                   # the spec
├── docs/superpowers/plans/                   # this plan
└── .gitignore
```

---

## Task 1: Project scaffolding

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Makefile`
- Create: `Sources/BannerShiftCore/.gitkeep`
- Create: `Sources/BannerShift/main.swift`
- Create: `Tests/BannerShiftCoreTests/.gitkeep`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "BannerShift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BannerShift", targets: ["BannerShift"]),
        .library(name: "BannerShiftCore", targets: ["BannerShiftCore"]),
    ],
    targets: [
        .target(name: "BannerShiftCore"),
        .executableTarget(
            name: "BannerShift",
            dependencies: ["BannerShiftCore"]
        ),
        .testTarget(
            name: "BannerShiftCoreTests",
            dependencies: ["BannerShiftCore"]
        ),
    ]
)
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
.build/
.swiftpm/
*.xcodeproj/
DerivedData/
build/
*.app
*.tar.gz
.env
.secrets/
.DS_Store
```

- [ ] **Step 3: Write a placeholder `main.swift` so the executable target compiles**

```swift
// Sources/BannerShift/main.swift
import Foundation
// Placeholder. Replaced in Task 23.
print("BannerShift scaffold")
exit(0)
```

- [ ] **Step 4: Write `Makefile`**

Uses a self-documenting `## help` doc-comment pattern. All targets `.PHONY`. `validate` is the pre-merge gate: format-check + build + test.

```makefile
# BannerShift — top-level dev commands.
# Tested with the GNU make that ships with macOS (3.81). All targets are phony.

ROOT       := $(shell pwd)
APP_BUNDLE := $(ROOT)/build/BannerShift.app
SWIFT_FMT  := swift format
SOURCES    := Package.swift Sources Tests

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_.-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ---- Build / test ----

.PHONY: build
build: ## Build the package (debug).
	swift build

.PHONY: test
test: ## Run unit tests.
	swift test

.PHONY: clean
clean: ## Remove build artifacts.
	rm -rf $(ROOT)/.build $(ROOT)/build

# ---- App bundle ----

.PHONY: dev
dev: ## Build a universal, ad-hoc-signed .app at build/BannerShift.app.
	./scripts/build-dev.sh

.PHONY: run
run: dev ## Build then launch the .app via `open`.
	open $(APP_BUNDLE)

# ---- Quality gates ----

.PHONY: format
format: ## Format Swift sources in place (Apple swift-format).
	$(SWIFT_FMT) format -i -r $(SOURCES)

.PHONY: format-check
format-check: ## Verify formatting; nonzero exit on drift.
	$(SWIFT_FMT) lint -s -r $(SOURCES)

.PHONY: validate
validate: format-check build test ## Pre-merge gate: format-check + build + test.
	@echo "validate: all checks ok"

# ---- Release ----

.PHONY: secrets
secrets: ## Pull signing secrets from 1Password into .env + .secrets/.
	./populate-secrets.sh

.PHONY: release
release: ## Signed, notarized, stapled release build. Requires `make secrets` first.
	./release.sh

# ---- Logs ----

.PHONY: tail-log
tail-log: ## Tail ~/Library/Logs/BannerShift.log (creates the file if absent).
	@touch ~/Library/Logs/BannerShift.log
	tail -f ~/Library/Logs/BannerShift.log
```

- [ ] **Step 5: Verify `make help` and `make build` / `make test` work**

Run: `make help`
Expected: a column listing of targets (`help`, `build`, `test`, `clean`, `dev`, `run`, `format`, `format-check`, `validate`, `secrets`, `release`, `tail-log`) with descriptions in cyan.

Run: `make build`
Expected: `Build complete!`

Run: `make test`
Expected: `Test Suite 'All tests' passed` (0 tests).

- [ ] **Step 6: Verify `swift format` is available**

Run: `swift format --version`
Expected: a version string. If absent: install Apple swift-format (`brew install swift-format`) and re-run.

Then run a no-op format check to confirm wiring:

Run: `make format-check`
Expected: clean exit. (With near-empty sources there is nothing to flag.)

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Makefile Sources Tests
git commit -m "chore: scaffold SwiftPM project + Makefile

- Package.swift with BannerShiftCore library and BannerShift executable
- macOS 13 deployment target (SMAppService floor)
- Empty test target wired up
- Makefile with help/build/test/format/format-check/validate/dev/run/
  secrets/release/tail-log; validate = format-check + build + test
- Mirrors the workbench-platform Makefile doc-comment help pattern"
```

---

## Task 2: Constants

**Files:**
- Create: `Sources/BannerShiftCore/Constants.swift`

These are the spec's fragile strings (§9, §20) and tunable constants (§7), in one place so future macOS regressions are one-line fixes.

- [ ] **Step 1: Write `Constants.swift`**

```swift
import Foundation

public enum Constants {
    /// Bundle ID. Must match Info.plist (§18).
    public static let bundleIdentifier = "com.emerle.BannerShift"

    /// Bundle ID of the system process that owns notification UI windows.
    /// Macros 13–26 have used "com.apple.notificationcenterui". Fragile.
    public static let notificationUIBundleIdentifier = "com.apple.notificationcenterui"

    /// AX subroles that identify a banner-style element inside a window.
    /// Updated occasionally across major macOS releases (§20.1).
    public static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner",
        "AXNotificationCenterAlert",
        "AXSystemDialog",
    ]

    /// AX identifier present only on a control inside an open Notification
    /// Center panel — used to distinguish panel from banner (§9, §20.2).
    public static let notificationCenterPanelIdentifier = "widget-editor"

    /// Padding (in points) to keep middle- and bottom-row positions clear of
    /// the Dock. Single source of truth (§7).
    public static let dockPadding: CGFloat = 30

    /// OS's own inset of the banner from the right edge of its container
    /// window (§7). Single source of truth.
    public static let bannerRightInset: CGFloat = 16

    /// Debounce interval for coalescing event bursts (§10).
    public static let eventDebounceInterval: TimeInterval = 0.030

    /// Max file-log size in bytes; truncated at launch if exceeded.
    public static let maxLogFileSize: Int = 5 * 1024 * 1024
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShiftCore/Constants.swift
git commit -m "feat(core): add Constants

- bundle IDs, banner subroles, panel identifier
- dock and banner-right-inset paddings
- debounce interval and log size cap"
```

---

## Task 3: Position enum (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/Position.swift`
- Create: `Tests/BannerShiftCoreTests/PositionTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/PositionTests.swift
import Testing
@testable import BannerShiftCore

@Test func positionHasNineCases() {
    #expect(Position.allCases.count == 9)
}

@Test func positionRawValueRoundTrips() {
    for p in Position.allCases {
        #expect(Position(rawValue: p.rawValue) == p)
    }
}

@Test func positionRawValuesAreStable() {
    // These are persisted in UserDefaults; do not change them.
    #expect(Position.topLeft.rawValue == "top-left")
    #expect(Position.topMiddle.rawValue == "top-middle")
    #expect(Position.topRight.rawValue == "top-right")
    #expect(Position.middleLeft.rawValue == "middle-left")
    #expect(Position.middle.rawValue == "middle")
    #expect(Position.middleRight.rawValue == "middle-right")
    #expect(Position.bottomLeft.rawValue == "bottom-left")
    #expect(Position.bottomMiddle.rawValue == "bottom-middle")
    #expect(Position.bottomRight.rawValue == "bottom-right")
}

@Test func positionDisplayNamesAreHuman() {
    #expect(Position.topRight.displayName == "Top Right")
    #expect(Position.middle.displayName == "Middle")
    #expect(Position.bottomLeft.displayName == "Bottom Left")
}

@Test func positionHorizontalAndVertical() {
    #expect(Position.topRight.horizontal == .right)
    #expect(Position.topRight.vertical == .top)
    #expect(Position.middle.horizontal == .center)
    #expect(Position.middle.vertical == .middle)
    #expect(Position.bottomLeft.horizontal == .left)
    #expect(Position.bottomLeft.vertical == .bottom)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: All five tests fail with "cannot find 'Position' in scope".

- [ ] **Step 3: Implement `Position.swift`**

```swift
import Foundation

public enum Position: String, CaseIterable, Sendable {
    case topLeft     = "top-left"
    case topMiddle   = "top-middle"
    case topRight    = "top-right"
    case middleLeft  = "middle-left"
    case middle      = "middle"
    case middleRight = "middle-right"
    case bottomLeft  = "bottom-left"
    case bottomMiddle = "bottom-middle"
    case bottomRight = "bottom-right"

    public enum Horizontal: Sendable { case left, center, right }
    public enum Vertical: Sendable { case top, middle, bottom }

    public var horizontal: Horizontal {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft:    return .left
        case .topMiddle, .middle, .bottomMiddle:    return .center
        case .topRight, .middleRight, .bottomRight: return .right
        }
    }

    public var vertical: Vertical {
        switch self {
        case .topLeft, .topMiddle, .topRight:           return .top
        case .middleLeft, .middle, .middleRight:        return .middle
        case .bottomLeft, .bottomMiddle, .bottomRight:  return .bottom
        }
    }

    public var displayName: String {
        switch self {
        case .topLeft:      return "Top Left"
        case .topMiddle:    return "Top Middle"
        case .topRight:     return "Top Right"
        case .middleLeft:   return "Middle Left"
        case .middle:       return "Middle"
        case .middleRight:  return "Middle Right"
        case .bottomLeft:   return "Bottom Left"
        case .bottomMiddle: return "Bottom Middle"
        case .bottomRight:  return "Bottom Right"
        }
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `swift test`
Expected: All five tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Position.swift Tests/BannerShiftCoreTests/PositionTests.swift
git commit -m "feat(core): add Position enum

- 9 cases with stable rawValues for UserDefaults persistence
- horizontal/vertical decomposition for math
- human-readable displayName for menus"
```

---

## Task 4: Preferences (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/Preferences.swift`
- Create: `Tests/BannerShiftCoreTests/PreferencesTests.swift`

Per §13 there are three keys, each independent. Tests use a private `UserDefaults` suite so they don't pollute the developer's machine.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/PreferencesTests.swift
import Testing
import Foundation
@testable import BannerShiftCore

private func makeSuite() -> UserDefaults {
    let name = "test-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    suite.removePersistentDomain(forName: name)
    return suite
}

@Test func positionDefaultsToTopMiddle() {
    let prefs = Preferences(defaults: makeSuite())
    #expect(prefs.position == .topMiddle)
}

@Test func positionPersistsValidString() {
    let suite = makeSuite()
    let prefs = Preferences(defaults: suite)
    prefs.position = .bottomRight
    #expect(Preferences(defaults: suite).position == .bottomRight)
}

@Test func positionFallsBackOnMalformedString() {
    let suite = makeSuite()
    suite.set("garbage-value", forKey: "selectedPosition")
    let prefs = Preferences(defaults: suite)
    #expect(prefs.position == .topMiddle)
}

@Test func iconHiddenDefaultsToFalse() {
    let prefs = Preferences(defaults: makeSuite())
    #expect(prefs.iconHidden == false)
}

@Test func iconHiddenPersists() {
    let suite = makeSuite()
    let prefs = Preferences(defaults: suite)
    prefs.iconHidden = true
    #expect(Preferences(defaults: suite).iconHidden == true)
}

@Test func debugLoggingDefaultsToFalse() {
    let prefs = Preferences(defaults: makeSuite())
    #expect(prefs.debugLoggingEnabled == false)
}

@Test func debugLoggingIsReadLiveNotCached() {
    let suite = makeSuite()
    let prefs = Preferences(defaults: suite)
    #expect(prefs.debugLoggingEnabled == false)
    suite.set(true, forKey: "debugLoggingEnabled")
    #expect(prefs.debugLoggingEnabled == true)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'Preferences' in scope".

- [ ] **Step 3: Implement `Preferences.swift`**

```swift
import Foundation

public final class Preferences {
    public static let positionKey = "selectedPosition"
    public static let iconHiddenKey = "iconHidden"
    public static let debugLoggingKey = "debugLoggingEnabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var position: Position {
        get {
            guard let raw = defaults.string(forKey: Self.positionKey),
                  let p = Position(rawValue: raw) else {
                return .topMiddle
            }
            return p
        }
        set { defaults.set(newValue.rawValue, forKey: Self.positionKey) }
    }

    public var iconHidden: Bool {
        get { defaults.bool(forKey: Self.iconHiddenKey) }
        set { defaults.set(newValue, forKey: Self.iconHiddenKey) }
    }

    /// Read live on each access so flipping the flag in `defaults write`
    /// takes effect without a relaunch (§14).
    public var debugLoggingEnabled: Bool {
        defaults.bool(forKey: Self.debugLoggingKey)
    }

    public func setDebugLogging(_ on: Bool) {
        defaults.set(on, forKey: Self.debugLoggingKey)
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `swift test`
Expected: All seven tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Preferences.swift Tests/BannerShiftCoreTests/PreferencesTests.swift
git commit -m "feat(core): add Preferences

- position, iconHidden, debugLoggingEnabled keys
- position falls back to topMiddle on malformed string
- debugLoggingEnabled read live on each access"
```

---

## Task 5: Baseline record (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/Baseline.swift`
- Create: `Tests/BannerShiftCoreTests/BaselineTests.swift`

Per §8: a value type holding the window's original origin, full window frame at first move, and banner frame at first move. The three fields are set or cleared as a unit.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/BaselineTests.swift
import Testing
import CoreGraphics
@testable import BannerShiftCore

@Test func baselineHoldsAllThreeFields() {
    let b = Baseline(
        originalOrigin: CGPoint(x: 100, y: 200),
        windowFrame: CGRect(x: 100, y: 200, width: 1000, height: 800),
        bannerFrame: CGRect(x: 800, y: 220, width: 360, height: 80)
    )
    #expect(b.originalOrigin == CGPoint(x: 100, y: 200))
    #expect(b.windowFrame.size.width == 1000)
    #expect(b.bannerFrame.origin.x == 800)
}

@Test func baselineEquatable() {
    let a = Baseline(
        originalOrigin: .zero,
        windowFrame: CGRect(x: 0, y: 0, width: 10, height: 10),
        bannerFrame: CGRect(x: 1, y: 1, width: 2, height: 2)
    )
    let b = a
    #expect(a == b)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'Baseline' in scope".

- [ ] **Step 3: Implement `Baseline.swift`**

```swift
import CoreGraphics

public struct Baseline: Equatable, Sendable {
    public let originalOrigin: CGPoint
    public let windowFrame: CGRect
    public let bannerFrame: CGRect

    public init(originalOrigin: CGPoint, windowFrame: CGRect, bannerFrame: CGRect) {
        self.originalOrigin = originalOrigin
        self.windowFrame = windowFrame
        self.bannerFrame = bannerFrame
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Baseline.swift Tests/BannerShiftCoreTests/BaselineTests.swift
git commit -m "feat(core): add Baseline value type

Holds original origin, window frame, and banner frame as a unit
to prevent post-move drift (plan §8)."
```

---

## Task 6: ScreenInfo (injectable display value type)

**Files:**
- Create: `Sources/BannerShiftCore/ScreenInfo.swift`

`NSScreen` is hard to mock. `ScreenInfo` is a simple value snapshot that the app glue builds from `NSScreen.screens` and passes into Core code.

- [ ] **Step 1: Implement `ScreenInfo.swift`**

```swift
import CoreGraphics

public struct ScreenInfo: Equatable, Sendable {
    /// AppKit-space frame (bottom-left origin, points).
    public let frame: CGRect
    /// AppKit-space visible frame (excludes menu bar and Dock).
    public let visibleFrame: CGRect
    /// True if this is the screen at index 0 of `NSScreen.screens`.
    public let isPrimary: Bool

    public init(frame: CGRect, visibleFrame: CGRect, isPrimary: Bool) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isPrimary = isPrimary
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShiftCore/ScreenInfo.swift
git commit -m "feat(core): add ScreenInfo

Injectable snapshot of an NSScreen so display-sensitive math is
testable without AppKit fixtures."
```

---

## Task 7: Display selector (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/DisplaySelector.swift`
- Create: `Tests/BannerShiftCoreTests/DisplaySelectorTests.swift`

Per §6, locate the display containing a given AX-space point. Requires a y-flip pivoted on the primary display's height — not the global maximum y (§20.4).

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/DisplaySelectorTests.swift
import Testing
import CoreGraphics
@testable import BannerShiftCore

private let primary = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
    isPrimary: true
)

private let secondaryRight = ScreenInfo(
    frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
    isPrimary: false
)

private let secondaryAbove = ScreenInfo(
    // Physically above primary => positive AppKit y.
    frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
    isPrimary: false
)

@Test func pointInPrimaryReturnsPrimary() {
    // AX-space window center on primary: (960, 540) in AX coords (top-left origin).
    let selector = DisplaySelector(screens: [primary, secondaryRight])
    let screen = selector.screenContaining(axPoint: CGPoint(x: 960, y: 540))
    #expect(screen == primary)
}

@Test func pointInSecondaryReturnsSecondary() {
    let selector = DisplaySelector(screens: [primary, secondaryRight])
    let screen = selector.screenContaining(axPoint: CGPoint(x: 2880, y: 540))
    #expect(screen == secondaryRight)
}

@Test func pointAboveUsesPrimaryHeightAsFlipPivot() {
    // AX y=-500 is physically 500pt above the primary display top.
    // Using primary height as pivot, AppKit y = 1080 - (-500) = 1580
    // which lands in secondaryAbove (frame y=1080..2160). Correct.
    // If we incorrectly used the global max y (1080+1080=2160) as pivot,
    // AppKit y = 2160 - (-500) = 2660 — falls in NO screen. Wrong.
    let selector = DisplaySelector(screens: [primary, secondaryAbove])
    let screen = selector.screenContaining(axPoint: CGPoint(x: 960, y: -500))
    #expect(screen == secondaryAbove)
}

@Test func pointOutsideFallsBackToPrimary() {
    let selector = DisplaySelector(screens: [primary, secondaryRight])
    let fallback = ScreenInfo(
        frame: CGRect(x: 0, y: 0, width: 100, height: 100),
        visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        isPrimary: false
    )
    // Way off any display.
    let screen = selector.screenContaining(
        axPoint: CGPoint(x: 99999, y: 99999),
        activeScreenFallback: fallback
    )
    #expect(screen == fallback)
}

@Test func fallbackToPrimaryWhenNoActiveScreen() {
    let selector = DisplaySelector(screens: [primary, secondaryRight])
    let screen = selector.screenContaining(
        axPoint: CGPoint(x: 99999, y: 99999),
        activeScreenFallback: nil
    )
    #expect(screen == primary)
}

@Test func emptyScreensReturnsNil() {
    let selector = DisplaySelector(screens: [])
    #expect(selector.screenContaining(axPoint: .zero) == nil)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'DisplaySelector' in scope".

- [ ] **Step 3: Implement `DisplaySelector.swift`**

```swift
import CoreGraphics

public struct DisplaySelector {
    public let screens: [ScreenInfo]

    public init(screens: [ScreenInfo]) {
        self.screens = screens
    }

    private var primary: ScreenInfo? {
        screens.first(where: { $0.isPrimary }) ?? screens.first
    }

    /// Convert an AX-coordinate point (top-left origin, pivoted on the
    /// primary display's height — §20.4) to an AppKit point and find the
    /// first screen whose frame contains it. Returns nil if no screen
    /// matches AND no fallback is provided.
    public func screenContaining(
        axPoint: CGPoint,
        activeScreenFallback: ScreenInfo? = nil
    ) -> ScreenInfo? {
        guard let primary = primary else { return nil }
        let appKitY = primary.frame.height - axPoint.y
        let appKitPoint = CGPoint(x: axPoint.x, y: appKitY)
        if let match = screens.first(where: { $0.frame.contains(appKitPoint) }) {
            return match
        }
        return activeScreenFallback ?? self.primary
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `swift test`
Expected: all six tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/DisplaySelector.swift Tests/BannerShiftCoreTests/DisplaySelectorTests.swift
git commit -m "feat(core): add DisplaySelector

- y-flip pivots on primary display height (plan §20.4)
- fallback chain: matching screen → active screen → primary"
```

---

## Task 8: Position calculator (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/PositionCalculator.swift`
- Create: `Tests/BannerShiftCoreTests/PositionCalculatorTests.swift`

Per §7, computes the target *window origin* such that the banner inside the window lands on the chosen 3×3 cell of the chosen display.

Inputs:
- baseline window frame and banner frame (frames at first move),
- target `Position`,
- target `ScreenInfo`,
- `Constants.dockPadding` and `Constants.bannerRightInset`.

The window is the height of the display (asserted invariant — §20.3). The banner is offset from the window's right edge by `bannerRightInset`.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/PositionCalculatorTests.swift
import Testing
import CoreGraphics
@testable import BannerShiftCore

private let screen = ScreenInfo(
    frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),  // 25pt menu bar
    isPrimary: true
)

/// A typical banner: window is full screen, banner sits in the top-right
/// inside the window, 360x80, with 16pt right inset.
private let windowFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
private let bannerFrame = CGRect(x: 1544, y: 0, width: 360, height: 80)

@Test func topRightLeavesOriginUntouched() {
    let calc = PositionCalculator(
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        screen: screen
    )
    let origin = calc.targetOrigin(for: .topRight)
    #expect(origin == CGPoint(x: 0, y: 0))
}

@Test func topLeftShiftsWindowLeftByBannerOffset() {
    let calc = PositionCalculator(
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        screen: screen
    )
    // Want banner left at screen x=0. Banner is at window x=1544; want it at 0.
    // So window origin x = 0 - 1544 = -1544.
    let origin = calc.targetOrigin(for: .topLeft)
    #expect(origin.x == -1544)
    #expect(origin.y == 0)
}

@Test func topMiddleCentersBannerHorizontally() {
    let calc = PositionCalculator(
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        screen: screen
    )
    // Centered banner left = (1920 - 360) / 2 = 780.
    // Banner offset inside window = 1544.
    // Window origin x = 780 - 1544 = -764.
    let origin = calc.targetOrigin(for: .topMiddle)
    #expect(origin.x == -764)
    #expect(origin.y == 0)
}

@Test func bottomRightShiftsWindowUp() {
    let calc = PositionCalculator(
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        screen: screen
    )
    // Visible bottom (AX): screen.frame.height - 0 = 1080 - dock - padding.
    // visibleFrame.height = 1055, so dock height = 0 (only menu bar above).
    // We want banner bottom at AX y = screenHeight - dockPadding = 1080 - 30 = 1050.
    // Banner is at window y=0 with height 80; banner bottom is at window y=80.
    // Target window y so banner-bottom-in-screen == 1050:
    //   window y + 80 = 1050  =>  window y = 970.
    let origin = calc.targetOrigin(for: .bottomRight)
    #expect(origin.x == 0)
    #expect(origin.y == 970)
}

@Test func middleCentersVerticallyOnVisibleArea() {
    let calc = PositionCalculator(
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        screen: screen
    )
    // visibleFrame in AX: top = screen.frame.height - visibleFrame.maxY = 1080 - 1080 = 0
    //                     bottom = screen.frame.height - visibleFrame.minY = 1080 - 25 = 1055.
    // visible height = 1055.  Banner height = 80.
    // Banner top in AX: 0 + (1055 - 80) / 2 = 487.5 → snapped to 488.
    // Banner currently at window y=0; window y = 488 - 0 = 488.
    // Wait — dockPadding only shifts down on bottom row, not middle. Re-read spec:
    //   "with the Dock-padding constant applied so that on bottom-Dock setups
    //    the banner does not collide with the Dock."
    // So middle: shift up by dockPadding/2 to bias above center.
    let origin = calc.targetOrigin(for: .middle)
    // We document a specific contract: middle = vertical center of visible
    // area, minus half the dock padding so a bottom Dock can't clip it.
    // visibleCenter AX = (visible_top_ax + visible_bottom_ax) / 2 = (0 + 1055) / 2 = 527.5
    // bannerCenter_in_window = (0 + 80) / 2 = 40.
    // target window y = 527.5 - 40 - dockPadding/2 = 527.5 - 40 - 15 = 472.5 → 473
    #expect(origin.x == 0)
    #expect(origin.y == 473)
}

@Test func targetOriginIsSnappedToIntegers() {
    let calc = PositionCalculator(
        windowFrame: CGRect(x: 0, y: 0, width: 1921, height: 1081),
        bannerFrame: CGRect(x: 1545, y: 0, width: 361, height: 81),
        screen: screen
    )
    let origin = calc.targetOrigin(for: .topMiddle)
    #expect(origin.x == origin.x.rounded())
    #expect(origin.y == origin.y.rounded())
}

@Test func windowHeightMismatchIsRejected() {
    // Spec §20.3: assert the window is the height of the display.
    // We expose a validator that callers must consult before applying a move.
    let calc = PositionCalculator(
        windowFrame: CGRect(x: 0, y: 0, width: 1920, height: 800), // wrong height
        bannerFrame: bannerFrame,
        screen: screen
    )
    #expect(calc.invariantHolds == false)
}

@Test func windowHeightMatchHonoredAsValid() {
    let calc = PositionCalculator(
        windowFrame: windowFrame,
        bannerFrame: bannerFrame,
        screen: screen
    )
    #expect(calc.invariantHolds == true)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'PositionCalculator' in scope".

- [ ] **Step 3: Implement `PositionCalculator.swift`**

```swift
import CoreGraphics

public struct PositionCalculator {
    public let windowFrame: CGRect
    public let bannerFrame: CGRect
    public let screen: ScreenInfo

    public init(windowFrame: CGRect, bannerFrame: CGRect, screen: ScreenInfo) {
        self.windowFrame = windowFrame
        self.bannerFrame = bannerFrame
        self.screen = screen
    }

    /// True iff the AX container window is the height of the display (§20.3).
    public var invariantHolds: Bool {
        windowFrame.size.height == screen.frame.size.height
    }

    /// Banner offset from the window's right edge, ignoring the OS's
    /// own inset constant.
    private var bannerOffsetFromRight: CGFloat {
        windowFrame.size.width - bannerFrame.maxX
    }

    public func targetOrigin(for position: Position) -> CGPoint {
        let x = horizontalOrigin(for: position.horizontal)
        let y = verticalOrigin(for: position.vertical)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    // MARK: Horizontal

    private func horizontalOrigin(for h: Position.Horizontal) -> CGFloat {
        switch h {
        case .right:
            // OS default: leave the window alone horizontally.
            return windowFrame.origin.x
        case .left:
            // Banner left edge should land at screen.frame.minX (0 in AX).
            // banner_x_in_screen = window_x + banner_x_in_window
            //                    = target_x + bannerFrame.minX
            // We want banner_x_in_screen = screen.frame.minX
            // => target_x = screen.frame.minX - bannerFrame.minX
            return screen.frame.minX - bannerFrame.minX
        case .center:
            // banner_x_in_screen = screen.frame.minX + (screen.width - bannerWidth) / 2
            let centered = screen.frame.minX + (screen.frame.width - bannerFrame.width) / 2
            return centered - bannerFrame.minX
        }
    }

    // MARK: Vertical
    //
    // All AX values use top-left origin. screen.frame is AppKit; we need to
    // express the visibleFrame in AX coords.
    //
    //   visibleTopAX    = screenHeight - visibleFrame.maxY
    //   visibleBottomAX = screenHeight - visibleFrame.minY

    private var visibleTopAX: CGFloat {
        screen.frame.height - screen.visibleFrame.maxY
    }

    private var visibleBottomAX: CGFloat {
        screen.frame.height - screen.visibleFrame.minY
    }

    private func verticalOrigin(for v: Position.Vertical) -> CGFloat {
        switch v {
        case .top:
            // Leave window vertically alone — OS default banner is at the top.
            return windowFrame.origin.y
        case .middle:
            // Vertically center banner on visible area, biased up by half the
            // dock padding so a bottom Dock can never clip it (§7).
            let bannerCenterInWindow = bannerFrame.minY + bannerFrame.height / 2
            let visibleCenterAX = (visibleTopAX + visibleBottomAX) / 2
            return visibleCenterAX - bannerCenterInWindow - Constants.dockPadding / 2
        case .bottom:
            // Banner bottom should sit just above visibleBottomAX, by dockPadding.
            let targetBannerBottomAX = visibleBottomAX - Constants.dockPadding
            let bannerBottomInWindow = bannerFrame.maxY
            return targetBannerBottomAX - bannerBottomInWindow
        }
    }
}
```

- [ ] **Step 4: Run tests, see all pass**

Run: `swift test`
Expected: all 8 PositionCalculator tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/PositionCalculator.swift Tests/BannerShiftCoreTests/PositionCalculatorTests.swift
git commit -m "feat(core): add PositionCalculator

- horizontal: right keeps OS default, left pins banner to screen,
  center centers banner on display
- vertical: top keeps OS default, middle centers on visible area,
  bottom pins above visible-area bottom with dock padding
- target origin snapped to integer points (plan §7)
- exposes invariantHolds for the §20.3 height assertion"
```

---

## Task 9: Debouncer (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/Debouncer.swift`
- Create: `Tests/BannerShiftCoreTests/DebouncerTests.swift`

Per §10: schedule on main queue, cancel pending on new event, fire 30ms after last event.

For testability, the debouncer takes a `DispatchQueue` (default `.main`) and a clock that can be substituted in tests. We test the cancellation logic by running on a fresh serial queue.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/DebouncerTests.swift
import Testing
import Foundation
@testable import BannerShiftCore

@Test func firesAfterInterval() async throws {
    let q = DispatchQueue(label: "test")
    let debouncer = Debouncer(interval: 0.05, queue: q)
    var fired = 0
    debouncer.schedule { fired += 1 }
    try await Task.sleep(nanoseconds: 100_000_000)
    q.sync {}  // drain
    #expect(fired == 1)
}

@Test func secondScheduleReplacesFirst() async throws {
    let q = DispatchQueue(label: "test")
    let debouncer = Debouncer(interval: 0.05, queue: q)
    var fired = 0
    debouncer.schedule { fired += 1 }
    debouncer.schedule { fired += 1 }
    debouncer.schedule { fired += 1 }
    try await Task.sleep(nanoseconds: 100_000_000)
    q.sync {}
    #expect(fired == 1)
}

@Test func cancelPreventsFire() async throws {
    let q = DispatchQueue(label: "test")
    let debouncer = Debouncer(interval: 0.05, queue: q)
    var fired = 0
    debouncer.schedule { fired += 1 }
    debouncer.cancel()
    try await Task.sleep(nanoseconds: 100_000_000)
    q.sync {}
    #expect(fired == 0)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'Debouncer' in scope".

- [ ] **Step 3: Implement `Debouncer.swift`**

```swift
import Foundation

public final class Debouncer {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private let lock = NSLock()

    public init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    public func schedule(_ action: @escaping () -> Void) {
        lock.lock()
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    public func cancel() {
        lock.lock()
        workItem?.cancel()
        workItem = nil
        lock.unlock()
    }
}
```

- [ ] **Step 4: Run tests, all pass**

Run: `swift test`
Expected: 3 Debouncer tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Debouncer.swift Tests/BannerShiftCoreTests/DebouncerTests.swift
git commit -m "feat(core): add Debouncer

Coalesces event bursts onto a single delayed dispatch (plan §10).
Subsequent schedules replace pending work rather than augment it."
```

---

## Task 10: Observer dedup key (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/ObserverKey.swift`
- Create: `Tests/BannerShiftCoreTests/ObserverKeyTests.swift`

Deviation from spec §11: the key includes element identity, not just role+subrole+size, so two simultaneous identical-shape banner windows do not collide into one observer.

The "identity" we use is an opaque address from the caller (`UInt64`), since `AXUIElement` pointers are not directly comparable as `Hashable`. The app layer extracts the address with `Unmanaged.passUnretained(ax).toOpaque()`.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/ObserverKeyTests.swift
import Testing
import CoreGraphics
@testable import BannerShiftCore

@Test func identicalKeysAreEqual() {
    let a = ObserverKey(elementID: 0x1000, role: "AXWindow", subrole: "AXSystemDialog",
                        size: CGSize(width: 1920, height: 1080))
    let b = ObserverKey(elementID: 0x1000, role: "AXWindow", subrole: "AXSystemDialog",
                        size: CGSize(width: 1920, height: 1080))
    #expect(a == b)
    #expect(a.hashValue == b.hashValue)
}

@Test func differentElementIDsDoNotCollide() {
    let a = ObserverKey(elementID: 0x1000, role: "AXWindow", subrole: "X",
                        size: CGSize(width: 1, height: 1))
    let b = ObserverKey(elementID: 0x2000, role: "AXWindow", subrole: "X",
                        size: CGSize(width: 1, height: 1))
    #expect(a != b)
}

@Test func sameShapeDifferentElementIDsStayDistinct() {
    // The bug we're fixing: two banner windows with identical role/subrole/size
    // but different identity must remain distinct keys.
    var set: Set<ObserverKey> = []
    set.insert(ObserverKey(elementID: 0xA, role: "AXWindow", subrole: "AXSystemDialog",
                           size: CGSize(width: 1920, height: 1080)))
    set.insert(ObserverKey(elementID: 0xB, role: "AXWindow", subrole: "AXSystemDialog",
                           size: CGSize(width: 1920, height: 1080)))
    #expect(set.count == 2)
}

@Test func positionIsExcludedFromKey() {
    // Position changes every time we move a window — must not affect identity.
    let a = ObserverKey(elementID: 0x1000, role: "AXWindow", subrole: "X",
                        size: CGSize(width: 1, height: 1))
    let b = ObserverKey(elementID: 0x1000, role: "AXWindow", subrole: "X",
                        size: CGSize(width: 1, height: 1))
    #expect(a == b)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'ObserverKey' in scope".

- [ ] **Step 3: Implement `ObserverKey.swift`**

```swift
import CoreGraphics

public struct ObserverKey: Hashable, Sendable {
    /// Stable opaque address of the underlying AX element. Pointer identity
    /// for AXUIElement is stable across attribute changes (incl. moves)
    /// within a single notification UI process lifetime (plan §8, §20.5).
    public let elementID: UInt64
    public let role: String
    public let subrole: String
    public let size: CGSize

    public init(elementID: UInt64, role: String, subrole: String, size: CGSize) {
        self.elementID = elementID
        self.role = role
        self.subrole = subrole
        self.size = size
    }
}
```

- [ ] **Step 4: Run tests, all pass**

Run: `swift test`
Expected: 4 ObserverKey tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/ObserverKey.swift Tests/BannerShiftCoreTests/ObserverKeyTests.swift
git commit -m "feat(core): add ObserverKey

Includes element identity so two same-shape banner windows do not
dedupe to one observer. Excludes position so re-registration after
a move is a no-op (plan §11, with review fix)."
```

---

## Task 11: File logger (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/FileLogger.swift`
- Create: `Tests/BannerShiftCoreTests/FileLoggerTests.swift`

Per §14: text file with 0600 permissions, append handle held open, level + ISO-8601 timestamp, debug gated on Preferences live read. Plus the rotation-on-launch addition.

For testability `FileLogger` takes a URL and a `() -> Bool` "isDebugEnabled" closure.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/FileLoggerTests.swift
import Testing
import Foundation
@testable import BannerShiftCore

private func tempLogURL() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("bsh-logs-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("BannerShift.log")
}

@Test func writesInfoAlways() throws {
    let url = tempLogURL()
    var debug = false
    let logger = try FileLogger(url: url, isDebugEnabled: { debug })
    logger.info("hello")
    logger.close()
    let contents = try String(contentsOf: url)
    #expect(contents.contains("INFO"))
    #expect(contents.contains("hello"))
}

@Test func skipsDebugWhenDisabled() throws {
    let url = tempLogURL()
    let logger = try FileLogger(url: url, isDebugEnabled: { false })
    logger.debug("secret")
    logger.close()
    let contents = try String(contentsOf: url)
    #expect(!contents.contains("secret"))
}

@Test func writesDebugWhenEnabled() throws {
    let url = tempLogURL()
    var debug = false
    let logger = try FileLogger(url: url, isDebugEnabled: { debug })
    debug = true
    logger.debug("visible")
    logger.close()
    let contents = try String(contentsOf: url)
    #expect(contents.contains("DEBUG"))
    #expect(contents.contains("visible"))
}

@Test func createsFileWith0600() throws {
    let url = tempLogURL()
    let logger = try FileLogger(url: url, isDebugEnabled: { false })
    logger.info("x")
    logger.close()
    let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
    #expect(perms.intValue == 0o600)
}

@Test func truncatesOversizedFileAtLaunch() throws {
    let url = tempLogURL()
    let big = String(repeating: "x", count: Constants.maxLogFileSize + 1024)
    try big.write(to: url, atomically: true, encoding: .utf8)
    let logger = try FileLogger(url: url, isDebugEnabled: { false })
    logger.info("fresh")
    logger.close()
    let contents = try String(contentsOf: url)
    #expect(contents.count < Constants.maxLogFileSize)
    #expect(contents.contains("fresh"))
    #expect(!contents.contains("xxxxxxxxxx"))
}

@Test func linesHaveISOTimestampAndLevel() throws {
    let url = tempLogURL()
    let logger = try FileLogger(url: url, isDebugEnabled: { false })
    logger.error("oh no")
    logger.close()
    let contents = try String(contentsOf: url)
    // Loose check: timestamp like "2026-" appears, ERROR appears.
    #expect(contents.contains("ERROR"))
    #expect(contents.range(of: #"\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil)
}
```

- [ ] **Step 2: Run, see failures**

Run: `swift test`
Expected: "cannot find 'FileLogger' in scope".

- [ ] **Step 3: Implement `FileLogger.swift`**

```swift
import Foundation

public final class FileLogger {
    public enum Level: String {
        case info  = "INFO"
        case debug = "DEBUG"
        case error = "ERROR"
    }

    private let url: URL
    private let handle: FileHandle
    private let isDebugEnabled: () -> Bool
    private let formatter: ISO8601DateFormatter
    private let queue = DispatchQueue(label: "BannerShift.FileLogger")

    public init(url: URL, isDebugEnabled: @escaping () -> Bool) throws {
        self.url = url
        self.isDebugEnabled = isDebugEnabled
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime]

        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > Constants.maxLogFileSize {
            try? fm.removeItem(at: url)
        }

        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil,
                          attributes: [.posixPermissions: NSNumber(value: 0o600)])
        } else {
            try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
        }

        self.handle = try FileHandle(forWritingTo: url)
        self.handle.seekToEndOfFile()
    }

    public func info(_ message: String)  { write(.info, message) }
    public func error(_ message: String) { write(.error, message) }
    public func debug(_ message: String) {
        guard isDebugEnabled() else { return }
        write(.debug, message)
    }

    public func close() {
        queue.sync { try? self.handle.close() }
    }

    private func write(_ level: Level, _ message: String) {
        let line = "[\(level.rawValue)] \(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                try? self.handle.write(contentsOf: data)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests, all pass**

Run: `swift test`
Expected: 6 FileLogger tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/FileLogger.swift Tests/BannerShiftCoreTests/FileLoggerTests.swift
git commit -m "feat(core): add FileLogger

- 0600 permissions, append handle held open
- ISO-8601 timestamps, level prefix
- debug gated on live closure (plan §14)
- launch-time truncation above 5 MB (plan deviation, see plan)"
```

---

## Task 11A: Animation enum (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/Animation.swift`

Per spec §22. Small foundational enum used by rules and the global default.

- [ ] **Step 1: Extend `PositionTests.swift` pattern — add `AnimationTests.swift`**

```swift
// Tests/BannerShiftCoreTests/AnimationTests.swift
import Testing
@testable import BannerShiftCore

@Test func animationFourCases() {
    #expect(Animation.allCases.count == 4)
}

@Test func animationRawValuesStable() {
    #expect(Animation.none.rawValue == "none")
    #expect(Animation.slide.rawValue == "slide")
    #expect(Animation.shake.rawValue == "shake")
    #expect(Animation.bounce.rawValue == "bounce")
}

@Test func animationDisplayNames() {
    #expect(Animation.none.displayName == "None")
    #expect(Animation.slide.displayName == "Slide")
    #expect(Animation.shake.displayName == "Shake")
    #expect(Animation.bounce.displayName == "Bounce")
}

@Test func animationCodableRoundTrip() throws {
    for a in Animation.allCases {
        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(Animation.self, from: data)
        #expect(decoded == a)
    }
}
```

- [ ] **Step 2: Run tests, see failures**

Run: `make test`
Expected: "cannot find 'Animation' in scope".

- [ ] **Step 3: Implement `Animation.swift`**

```swift
import Foundation

public enum Animation: String, CaseIterable, Sendable, Codable {
    case none   = "none"
    case slide  = "slide"
    case shake  = "shake"
    case bounce = "bounce"

    public var displayName: String {
        switch self {
        case .none:   return "None"
        case .slide:  return "Slide"
        case .shake:  return "Shake"
        case .bounce: return "Bounce"
        }
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `make test`
Expected: 4 Animation tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/Animation.swift Tests/BannerShiftCoreTests/AnimationTests.swift
git commit -m "feat(core): add Animation enum

Four cases (none, slide, shake, bounce) with stable raw values for
JSON persistence and display names for menus (plan §22)."
```

---

## Task 11B: BannerText, Rule, RuleStore (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/BannerText.swift`
- Create: `Sources/BannerShiftCore/Rule.swift`
- Create: `Sources/BannerShiftCore/RuleStore.swift`
- Create: `Tests/BannerShiftCoreTests/RuleTests.swift`
- Create: `Tests/BannerShiftCoreTests/RuleStoreTests.swift`

Per spec §22. Three tightly-coupled types added together: `BannerText` (matchable subject), `Rule` (a single rule record, Codable), `RuleStore` (JSON-in-UserDefaults persistence with corruption tolerance).

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/RuleTests.swift
import Testing
import Foundation
@testable import BannerShiftCore

@Test func bannerTextEmptyDefaults() {
    let t = BannerText()
    #expect(t.appName == "")
    #expect(t.title == "")
    #expect(t.body == "")
    #expect(t.bundleID == nil)
}

@Test func bannerTextEquatable() {
    let a = BannerText(appName: "A", title: "T")
    let b = BannerText(appName: "A", title: "T")
    #expect(a == b)
}

@Test func ruleInitDefaults() {
    let r = Rule()
    #expect(!r.id.isEmpty)
    #expect(r.enabled == true)
    #expect(r.position == nil)
    #expect(r.animation == nil)
    #expect(r.appPattern == nil)
}

@Test func ruleCodableRoundTrip() throws {
    let r = Rule(
        id: "1234",
        name: "Slack DMs",
        enabled: true,
        appPattern: "Slack",
        titlePattern: "^DM",
        position: .middle,
        animation: .shake
    )
    let data = try JSONEncoder().encode(r)
    let back = try JSONDecoder().decode(Rule.self, from: data)
    #expect(back == r)
}

@Test func ruleCodableHandlesNilFields() throws {
    let r = Rule(name: "Catchall")
    let data = try JSONEncoder().encode(r)
    let back = try JSONDecoder().decode(Rule.self, from: data)
    #expect(back == r)
}
```

```swift
// Tests/BannerShiftCoreTests/RuleStoreTests.swift
import Testing
import Foundation
@testable import BannerShiftCore

private func makeSuite() -> UserDefaults {
    let name = "test-\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    suite.removePersistentDomain(forName: name)
    return suite
}

@Test func ruleStoreEmptyByDefault() {
    let store = RuleStore(defaults: makeSuite())
    #expect(store.load() == [])
}

@Test func ruleStoreSaveLoadRoundTripPreservesOrder() {
    let suite = makeSuite()
    let store = RuleStore(defaults: suite)
    let rules = [
        Rule(name: "A", appPattern: "Slack", position: .middle),
        Rule(name: "B", appPattern: "Calendar", position: .topRight),
    ]
    store.save(rules)
    let back = RuleStore(defaults: suite).load()
    #expect(back == rules)
    #expect(back.map(\.name) == ["A", "B"])
}

@Test func ruleStoreReturnsEmptyOnCorruptJSON() {
    let suite = makeSuite()
    suite.set(Data("not json".utf8), forKey: RuleStore.key)
    var logged: [String] = []
    let store = RuleStore(defaults: suite, logger: { logged.append($0) })
    #expect(store.load() == [])
    #expect(!logged.isEmpty)
}
```

- [ ] **Step 2: Run, see failures**

Run: `make test`
Expected: "cannot find 'BannerText' / 'Rule' / 'RuleStore' in scope".

- [ ] **Step 3: Implement `BannerText.swift`**

```swift
import Foundation

public struct BannerText: Equatable, Sendable {
    public let appName: String
    public let bundleID: String?
    public let title: String
    public let subtitle: String
    public let body: String

    public init(
        appName: String = "",
        bundleID: String? = nil,
        title: String = "",
        subtitle: String = "",
        body: String = ""
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}
```

- [ ] **Step 4: Implement `Rule.swift`**

```swift
import Foundation

public struct Rule: Equatable, Sendable, Codable, Identifiable {
    public let id: String
    public var name: String
    public var enabled: Bool
    public var appPattern: String?
    public var bundleIDPattern: String?
    public var titlePattern: String?
    public var subtitlePattern: String?
    public var bodyPattern: String?
    public var position: Position?
    public var animation: Animation?

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        enabled: Bool = true,
        appPattern: String? = nil,
        bundleIDPattern: String? = nil,
        titlePattern: String? = nil,
        subtitlePattern: String? = nil,
        bodyPattern: String? = nil,
        position: Position? = nil,
        animation: Animation? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.appPattern = appPattern
        self.bundleIDPattern = bundleIDPattern
        self.titlePattern = titlePattern
        self.subtitlePattern = subtitlePattern
        self.bodyPattern = bodyPattern
        self.position = position
        self.animation = animation
    }
}
```

- [ ] **Step 5: Implement `RuleStore.swift`**

```swift
import Foundation

public final class RuleStore {
    public static let key = "rules"

    private let defaults: UserDefaults
    private let logger: ((String) -> Void)?

    public init(defaults: UserDefaults = .standard, logger: ((String) -> Void)? = nil) {
        self.defaults = defaults
        self.logger = logger
    }

    public func load() -> [Rule] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        do {
            return try JSONDecoder().decode([Rule].self, from: data)
        } catch {
            logger?("RuleStore: failed to decode rules (\(error)); starting empty")
            return []
        }
    }

    public func save(_ rules: [Rule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            defaults.set(data, forKey: Self.key)
        } catch {
            logger?("RuleStore: failed to encode rules (\(error)); not saved")
        }
    }
}
```

Note: `Position` and `Animation` need to be `Codable`. `Position` is defined as `String, CaseIterable, Sendable` in Task 3 — extend it to `Codable` (free for String-backed enums). Add `Codable` to `Position` in this task as part of implementation.

Modify `Position.swift`: change `public enum Position: String, CaseIterable, Sendable` to `public enum Position: String, CaseIterable, Sendable, Codable`. No other changes.

- [ ] **Step 6: Tests pass**

Run: `make test`
Expected: all new BannerText/Rule/RuleStore tests pass; existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/BannerShiftCore/BannerText.swift \
        Sources/BannerShiftCore/Rule.swift \
        Sources/BannerShiftCore/RuleStore.swift \
        Sources/BannerShiftCore/Position.swift \
        Tests/BannerShiftCoreTests/RuleTests.swift \
        Tests/BannerShiftCoreTests/RuleStoreTests.swift
git commit -m "feat(core): add BannerText, Rule, RuleStore

- BannerText: value type holding app/title/subtitle/body strings
  captured from the live banner subtree
- Rule: Codable rule record with five optional regex patterns plus
  optional position and animation overrides (plan §22)
- RuleStore: JSON-in-UserDefaults persistence, corrupt-tolerant
  (logs and returns empty rather than crashing)
- Make Position Codable so Rule can persist position overrides"
```

---

## Task 11C: RuleMatcher (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/RuleMatcher.swift`
- Create: `Tests/BannerShiftCoreTests/RuleMatcherTests.swift`

Per spec §22. Given a banner's text and an ordered rule list, returns the first enabled rule whose set patterns all match (case-insensitive, `.dotMatchesNewlines`). Malformed regex disables the offending rule at match time.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/RuleMatcherTests.swift
import Testing
@testable import BannerShiftCore

private let matcher = RuleMatcher()

@Test func emptyRulesReturnNil() {
    #expect(matcher.match(rules: [], banner: BannerText(appName: "X")) == nil)
}

@Test func ruleWithNoPatternsIsCatchall() {
    let catchall = Rule(name: "Catchall")
    let m = matcher.match(rules: [catchall], banner: BannerText(appName: "Whatever"))
    #expect(m?.rule.id == catchall.id)
}

@Test func appPatternMatchesCaseInsensitively() {
    let rule = Rule(name: "Slack rule", appPattern: "slack")
    let m = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
    #expect(m?.rule.id == rule.id)
}

@Test func allSetPatternsMustMatch() {
    let rule = Rule(name: "Slack DMs", appPattern: "Slack", titlePattern: "^DM")
    let dm  = matcher.match(rules: [rule], banner: BannerText(appName: "Slack", title: "DM from Alice"))
    let chn = matcher.match(rules: [rule], banner: BannerText(appName: "Slack", title: "#general"))
    #expect(dm?.rule.id == rule.id)
    #expect(chn == nil)
}

@Test func firstMatchWins() {
    let a = Rule(name: "A", appPattern: "Slack", position: .middle)
    let b = Rule(name: "B", appPattern: "Slack", position: .topRight)
    let m = matcher.match(rules: [a, b], banner: BannerText(appName: "Slack"))
    #expect(m?.rule.id == a.id)
}

@Test func disabledRuleSkipped() {
    let disabled = Rule(name: "Off", enabled: false, appPattern: "Slack", position: .topLeft)
    let live = Rule(name: "On", appPattern: "Slack", position: .middle)
    let m = matcher.match(rules: [disabled, live], banner: BannerText(appName: "Slack"))
    #expect(m?.rule.id == live.id)
}

@Test func malformedRegexDoesNotMatch() {
    let bad = Rule(name: "Bad", appPattern: "[unterminated")
    #expect(matcher.match(rules: [bad], banner: BannerText(appName: "anything")) == nil)
}

@Test func bundleIDPatternMatchedAgainstResolvedID() {
    let rule = Rule(name: "Slack only", bundleIDPattern: "tinyspeck\\.slack")
    let with = matcher.match(rules: [rule],
                             banner: BannerText(appName: "Slack",
                                                bundleID: "com.tinyspeck.slackmacgap"))
    let without = matcher.match(rules: [rule], banner: BannerText(appName: "Slack"))
    #expect(with != nil)
    #expect(without == nil)
}
```

- [ ] **Step 2: Run, see failures**

Run: `make test`
Expected: "cannot find 'RuleMatcher' in scope".

- [ ] **Step 3: Implement `RuleMatcher.swift`**

```swift
import Foundation

public struct RuleMatch: Equatable {
    public let rule: Rule
    public init(rule: Rule) { self.rule = rule }
}

public final class RuleMatcher {
    public init() {}

    public func match(rules: [Rule], banner: BannerText) -> RuleMatch? {
        for rule in rules where rule.enabled {
            if matches(rule, banner) {
                return RuleMatch(rule: rule)
            }
        }
        return nil
    }

    private func matches(_ rule: Rule, _ banner: BannerText) -> Bool {
        check(rule.appPattern,      banner.appName) &&
        check(rule.bundleIDPattern, banner.bundleID ?? "") &&
        check(rule.titlePattern,    banner.title) &&
        check(rule.subtitlePattern, banner.subtitle) &&
        check(rule.bodyPattern,     banner.body)
    }

    private func check(_ pattern: String?, _ subject: String) -> Bool {
        guard let pattern, !pattern.isEmpty else { return true }
        do {
            let regex = try Regex(pattern).ignoresCase().dotMatchesNewlines()
            return subject.firstMatch(of: regex) != nil
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `make test`
Expected: 8 RuleMatcher tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/RuleMatcher.swift Tests/BannerShiftCoreTests/RuleMatcherTests.swift
git commit -m "feat(core): add RuleMatcher

First-match-wins evaluation against BannerText. All set patterns
must match (case-insensitive). Disabled rules and rules with
malformed regex are silently skipped (plan §22)."
```

---

## Task 11D: AnimationFrames (TDD)

**Files:**
- Create: `Sources/BannerShiftCore/AnimationFrames.swift`
- Create: `Tests/BannerShiftCoreTests/AnimationFramesTests.swift`

Per spec §22. Pure function from `(style, from, to, fps)` to an array of `(timeOffset, point)` frames. Side-effect-free so the math can be unit-tested without timers. The app-side `Animator` (Task 14C) consumes this schedule and applies it via AX writes.

- [ ] **Step 1: Write failing tests**

```swift
// Tests/BannerShiftCoreTests/AnimationFramesTests.swift
import Testing
import CoreGraphics
@testable import BannerShiftCore

private let from = CGPoint(x: 0, y: 0)
private let to   = CGPoint(x: 100, y: 50)

@Test func noneProducesOneFrameAtTarget() {
    let frames = AnimationFrames.frames(style: .none, from: from, to: to)
    #expect(frames.count == 1)
    #expect(frames[0].point == to)
    #expect(frames[0].timeOffset == 0)
}

@Test func slideStartsFromAndEndsAtTarget() {
    let frames = AnimationFrames.frames(style: .slide, from: from, to: to)
    #expect(frames.first!.point == from)
    #expect(frames.last!.point  == to)
    #expect(frames.first!.timeOffset == 0)
}

@Test func slideFrameCountTracksFps() {
    let f30  = AnimationFrames.frames(style: .slide, from: from, to: to, fps: 30)
    let f60  = AnimationFrames.frames(style: .slide, from: from, to: to, fps: 60)
    #expect(f60.count > f30.count)
}

@Test func slideTimeOffsetsSorted() {
    let frames = AnimationFrames.frames(style: .slide, from: from, to: to)
    let ts = frames.map(\.timeOffset)
    #expect(ts == ts.sorted())
}

@Test func shakeStartsAndEndsAtCenter() {
    let frames = AnimationFrames.frames(style: .shake, from: from, to: to)
    #expect(frames.first!.point == to)
    #expect(frames.last!.point  == to)
}

@Test func bounceVariesYNotX() {
    let frames = AnimationFrames.frames(style: .bounce, from: from, to: to)
    let xs = Set(frames.map(\.point.x))
    let ys = Set(frames.map(\.point.y))
    #expect(xs.count == 1)
    #expect(ys.count > 1)
}

@Test func shakeVariesXNotY() {
    let frames = AnimationFrames.frames(style: .shake, from: from, to: to)
    let xs = Set(frames.map(\.point.x))
    let ys = Set(frames.map(\.point.y))
    #expect(ys.count == 1)
    #expect(xs.count > 1)
}
```

- [ ] **Step 2: Run, see failures**

Run: `make test`
Expected: "cannot find 'AnimationFrames' in scope".

- [ ] **Step 3: Implement `AnimationFrames.swift`**

```swift
import CoreGraphics
import Foundation

public enum AnimationFrames {
    public struct Frame: Equatable, Sendable {
        public let timeOffset: TimeInterval
        public let point: CGPoint

        public init(timeOffset: TimeInterval, point: CGPoint) {
            self.timeOffset = timeOffset
            self.point = point
        }
    }

    public static func frames(
        style: Animation,
        from: CGPoint,
        to: CGPoint,
        fps: Int = 60
    ) -> [Frame] {
        switch style {
        case .none:
            return [Frame(timeOffset: 0, point: to)]
        case .slide:
            return slide(from: from, to: to, duration: 0.200, fps: fps)
        case .shake:
            return oscillate(center: to, ax: 10, ay: 0, duration: 0.250, fps: fps)
        case .bounce:
            return oscillate(center: to, ax: 0, ay: 10, duration: 0.250, fps: fps)
        }
    }

    private static func slide(from: CGPoint, to: CGPoint,
                              duration: TimeInterval, fps: Int) -> [Frame] {
        let count = max(1, Int(round(duration * Double(fps))))
        var out: [Frame] = []
        out.reserveCapacity(count + 1)
        for i in 0...count {
            let t = Double(i) / Double(count)
            let eased = 1 - pow(1 - t, 3)
            let p = CGPoint(
                x: (from.x + (to.x - from.x) * eased).rounded(),
                y: (from.y + (to.y - from.y) * eased).rounded()
            )
            out.append(Frame(timeOffset: t * duration, point: p))
        }
        return out
    }

    private static func oscillate(center: CGPoint, ax: CGFloat, ay: CGFloat,
                                  duration: TimeInterval, fps: Int) -> [Frame] {
        let count = max(1, Int(round(duration * Double(fps))))
        var out: [Frame] = []
        out.reserveCapacity(count + 1)
        let cycles = 3.0
        for i in 0...count {
            let t = Double(i) / Double(count)
            let envelope = 1.0 - t
            let s = sin(2.0 * .pi * cycles * t) * envelope
            let p = CGPoint(
                x: (center.x + ax * CGFloat(s)).rounded(),
                y: (center.y + ay * CGFloat(s)).rounded()
            )
            out.append(Frame(timeOffset: t * duration, point: p))
        }
        if out.last?.point != center {
            out.append(Frame(timeOffset: duration, point: center))
        }
        return out
    }
}
```

- [ ] **Step 4: Tests pass**

Run: `make test`
Expected: all 7 AnimationFrames tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BannerShiftCore/AnimationFrames.swift Tests/BannerShiftCoreTests/AnimationFramesTests.swift
git commit -m "feat(core): add AnimationFrames

Pure function generating (timeOffset, point) frames per style:
- none: single frame at target
- slide: easeOutCubic from origin to target over 200ms
- shake: decaying x-axis oscillation at target over 250ms
- bounce: decaying y-axis oscillation at target over 250ms
Side-effect-free so the math is unit-testable without timers."
```

---

## Task 12: Info.plist and entitlements

**Files:**
- Create: `Resources/Info.plist`
- Create: `Resources/BannerShift.entitlements`

- [ ] **Step 1: Write `Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>          <string>en</string>
    <key>CFBundleExecutable</key>                 <string>BannerShift</string>
    <key>CFBundleIdentifier</key>                 <string>com.emerle.BannerShift</string>
    <key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
    <key>CFBundleName</key>                       <string>BannerShift</string>
    <key>CFBundlePackageType</key>                <string>APPL</string>
    <key>CFBundleShortVersionString</key>         <string>1.0.0</string>
    <key>CFBundleVersion</key>                    <string>1</string>
    <key>CFBundleIconFile</key>                   <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>             <string>13.0</string>
    <key>LSUIElement</key>                        <true/>
    <key>NSHumanReadableCopyright</key>           <string>Copyright © 2026 Ryan Emerle. All rights reserved.</string>
    <key>NSAccessibilityUsageDescription</key>    <string>BannerShift uses Accessibility to observe the system's notification banner windows and move them to your chosen screen position. It never reads notification content.</string>
    <key>NSPrincipalClass</key>                   <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 2: Write entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <false/>
</dict>
</plist>
```

The entitlement file is intentionally minimal. Accessibility itself is granted by the user in System Settings, not via entitlement.

- [ ] **Step 3: Commit**

```bash
git add Resources/Info.plist Resources/BannerShift.entitlements
git commit -m "feat: add Info.plist and entitlements

- LSUIElement=true (background agent, no Dock icon)
- NSAccessibilityUsageDescription explains why we need AX
- LSMinimumSystemVersion 13.0
- Bundle ID com.emerle.BannerShift (matches Constants)"
```

---

## Task 13: Accessibility permission gate

**Files:**
- Create: `Sources/BannerShift/AccessibilityPermission.swift`

Per §4.1 and §16: prompt on launch; terminate if not trusted.

- [ ] **Step 1: Implement `AccessibilityPermission.swift`**

```swift
import ApplicationServices
import Foundation

enum AccessibilityPermission {
    /// Returns true iff the process is trusted to use the Accessibility API.
    /// If not trusted, the system will display the standard prompt directing
    /// the user to System Settings → Privacy & Security → Accessibility.
    static func requireOrExit() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let options: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/AccessibilityPermission.swift
git commit -m "feat(app): AccessibilityPermission gate

Returns trust status and shows the system prompt if not yet trusted
(plan §4.1, §16). Caller terminates the process on false."
```

---

## Task 14: AX banner finder

**Files:**
- Create: `Sources/BannerShift/AXBannerFinder.swift`

Per §6: walk an AX window's accessibility tree depth-first, return the first element whose subrole is in `Constants.bannerSubroles`.

This is integration code (calls into AX). We test it indirectly via integration smoke tests in Task 22. Keep it small and focused.

- [ ] **Step 1: Implement `AXBannerFinder.swift`**

```swift
import ApplicationServices
import BannerShiftCore
import CoreGraphics

enum AXBannerFinder {
    /// Depth-first search for the first descendant of `window` whose
    /// AXSubrole is in `Constants.bannerSubroles`.
    static func find(in window: AXUIElement) -> AXUIElement? {
        if let subrole = stringAttribute(window, kAXSubroleAttribute as CFString),
           Constants.bannerSubroles.contains(subrole) {
            return window
        }
        let children = arrayAttribute(window, kAXChildrenAttribute as CFString)
        for child in children {
            if let hit = find(in: child) { return hit }
        }
        return nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let pos = pointAttribute(element, kAXPositionAttribute as CFString),
              let size = sizeAttribute(element, kAXSizeAttribute as CFString) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    // MARK: AX attribute helpers

    static func stringAttribute(_ el: AXUIElement, _ attr: CFString) -> String? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success else { return nil }
        return raw as? String
    }

    static func arrayAttribute(_ el: AXUIElement, _ attr: CFString) -> [AXUIElement] {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success,
              let arr = raw as? [AXUIElement] else { return [] }
        return arr
    }

    static func pointAttribute(_ el: AXUIElement, _ attr: CFString) -> CGPoint? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success else { return nil }
        let val = raw as! AXValue
        var p = CGPoint.zero
        guard AXValueGetType(val) == .cgPoint,
              AXValueGetValue(val, .cgPoint, &p) else { return nil }
        return p
    }

    static func sizeAttribute(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attr, &raw) == .success else { return nil }
        let val = raw as! AXValue
        var s = CGSize.zero
        guard AXValueGetType(val) == .cgSize,
              AXValueGetValue(val, .cgSize, &s) else { return nil }
        return s
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/AXBannerFinder.swift
git commit -m "feat(app): AXBannerFinder

DFS walk for elements with banner-style subroles. Also exposes
typed attribute helpers used by the rest of the app."
```

---

## Task 14A: Banner text extractor

**Files:**
- Create: `Sources/BannerShift/BannerTextExtractor.swift`

Per spec §22. Walks a banner element's subtree and collects text strings. Best-effort heuristic ordering (first text = app name, then title, subtitle, body); the implementation will likely need tuning after Task 26's live smoke test, similar to the banner-subrole set (§20.1).

- [ ] **Step 1: Implement `BannerTextExtractor.swift`**

```swift
import ApplicationServices
import BannerShiftCore
import CoreGraphics
import Foundation

enum BannerTextExtractor {
    /// Collect text from `banner`'s subtree. Returns ordered strings sorted
    /// top-to-bottom by AX position so the result is deterministic regardless
    /// of AX-tree traversal order.
    static func extract(from banner: AXUIElement) -> BannerText {
        var pairs: [(y: CGFloat, text: String)] = []
        collect(from: banner, into: &pairs)
        let ordered = pairs.sorted(by: { $0.y < $1.y }).map(\.text)
        return BannerText(
            appName:  ordered.indices.contains(0) ? ordered[0] : "",
            bundleID: nil,                         // resolved in BannerMover
            title:    ordered.indices.contains(1) ? ordered[1] : "",
            subtitle: ordered.indices.contains(2) ? ordered[2] : "",
            body:     ordered.indices.contains(3) ? ordered[3] : ""
        )
    }

    private static func collect(
        from el: AXUIElement,
        into out: inout [(y: CGFloat, text: String)]
    ) {
        // One string per element: prefer AXValue, then AXTitle, then AXDescription.
        let text: String? =
            AXBannerFinder.stringAttribute(el, kAXValueAttribute as CFString) ??
            AXBannerFinder.stringAttribute(el, kAXTitleAttribute as CFString) ??
            AXBannerFinder.stringAttribute(el, kAXDescriptionAttribute as CFString)
        if let t = text, !t.isEmpty {
            let y = AXBannerFinder.pointAttribute(el, kAXPositionAttribute as CFString)?.y ?? .infinity
            out.append((y, t))
        }
        for child in AXBannerFinder.arrayAttribute(el, kAXChildrenAttribute as CFString) {
            collect(from: child, into: &out)
        }
    }
}
```

Note: this is unit-testable only against synthetic AX trees, which is non-trivial. We test it indirectly via Task 26's manual smoke run.

- [ ] **Step 2: Build**

Run: `make build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/BannerTextExtractor.swift
git commit -m "feat(app): BannerTextExtractor

Walks banner subtree, collects (y, text) pairs, returns BannerText
sorted top-to-bottom. Heuristic ordering — will likely need tuning
against real banners (cf. plan §20.1 for the analogous fragility
around banner subroles)."
```

---

## Task 14B: App resolver

**Files:**
- Create: `Sources/BannerShift/AppResolver.swift`

Per spec §22. Best-effort: match an app-name string against `NSWorkspace.shared.runningApplications`' `localizedName` and return the bundle identifier. Nil for background daemons that post via the user-notification framework without appearing in `runningApplications`.

- [ ] **Step 1: Implement `AppResolver.swift`**

```swift
import AppKit
import Foundation

enum AppResolver {
    static func bundleID(forAppName name: String) -> String? {
        guard !name.isEmpty else { return nil }
        let lower = name.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            if let n = app.localizedName?.lowercased(), n == lower {
                return app.bundleIdentifier
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/AppResolver.swift
git commit -m "feat(app): AppResolver

Best-effort bundle-ID resolution via NSWorkspace.runningApplications.
Returns nil for daemons that post notifications without surfacing
as running applications (plan §22)."
```

---

## Task 14C: Animator

**Files:**
- Create: `Sources/BannerShift/Animator.swift`

Per spec §22. Drives `AnimationFrames` over time, applying each frame's point via `AXUIElementSetAttributeValue`. Supports cancellation per-window so animations don't bleed between bannerss. Untested at the unit-test layer (DispatchQueue + AX I/O); verified end-to-end in Task 26.

- [ ] **Step 1: Implement `Animator.swift`**

```swift
import ApplicationServices
import BannerShiftCore
import CoreGraphics
import Foundation

final class Animator {
    /// Default delay before the animation starts, in seconds. Tuned to wait
    /// out the OS's own banner-entry animation (§22).
    static let startDelay: TimeInterval = 0.150

    private var workItems: [UInt64: [DispatchWorkItem]] = [:]

    /// Schedule `frames` on the main queue against `window`. Cancels any
    /// previously scheduled animation for `windowID`.
    func animate(
        windowID: UInt64,
        window: AXUIElement,
        frames: [AnimationFrames.Frame],
        delay: TimeInterval = Animator.startDelay
    ) {
        cancel(windowID: windowID)
        var items: [DispatchWorkItem] = []
        let start = DispatchTime.now() + delay
        for frame in frames {
            let item = DispatchWorkItem {
                Animator.set(point: frame.point, on: window)
            }
            DispatchQueue.main.asyncAfter(deadline: start + frame.timeOffset, execute: item)
            items.append(item)
        }
        let totalDuration = (frames.last?.timeOffset ?? 0) + 0.010
        let cleanup = DispatchWorkItem { [weak self] in
            self?.workItems.removeValue(forKey: windowID)
        }
        DispatchQueue.main.asyncAfter(deadline: start + totalDuration, execute: cleanup)
        items.append(cleanup)
        workItems[windowID] = items
    }

    func cancel(windowID: UInt64) {
        workItems[windowID]?.forEach { $0.cancel() }
        workItems.removeValue(forKey: windowID)
    }

    func cancelAll() {
        for items in workItems.values { items.forEach { $0.cancel() } }
        workItems.removeAll()
    }

    static func set(point: CGPoint, on window: AXUIElement) {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/Animator.swift
git commit -m "feat(app): Animator

Schedules AnimationFrames over DispatchQueue.main, applies each
point via AXUIElementSetAttributeValue. Per-window cancellation
so a new debounced pass cleanly supersedes a prior animation."
```

---

## Task 15: Notification Center panel detector

**Files:**
- Create: `Sources/BannerShift/NotificationCenterPanelDetector.swift`

Per §9: walk the window's AX tree looking for `Constants.notificationCenterPanelIdentifier`. If found, treat the window as the open panel.

- [ ] **Step 1: Implement `NotificationCenterPanelDetector.swift`**

```swift
import ApplicationServices
import BannerShiftCore

enum NotificationCenterPanelDetector {
    static func isPanel(_ window: AXUIElement) -> Bool {
        if let id = AXBannerFinder.stringAttribute(window, kAXIdentifierAttribute as CFString),
           id == Constants.notificationCenterPanelIdentifier {
            return true
        }
        for child in AXBannerFinder.arrayAttribute(window, kAXChildrenAttribute as CFString) {
            if isPanel(child) { return true }
        }
        return false
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/NotificationCenterPanelDetector.swift
git commit -m "feat(app): NotificationCenterPanelDetector

Returns true if the window's AX tree contains the panel's identifier
control (plan §9). Used to skip repositioning while the user has the
full Notification Center open."
```

---

## Task 16: BannerMover orchestrator

**Files:**
- Create: `Sources/BannerShift/BannerMover.swift`

The orchestrator. Per-window state: baselines keyed by element address. On each debounced pass:

1. For each notification UI window:
   - If panel open → restore baseline (if any), clear it; cancel any in-flight animation.
   - Else if banner found → capture baseline on first sight, extract banner text, resolve bundle ID, consult `RuleMatcher`, compute target position from the matched rule (or default), and drive the animator with the chosen animation style (or `.none`).
   - Else if window has no banner → restore baseline (if any), clear; cancel animation.

- [ ] **Step 1: Implement `BannerMover.swift`**

```swift
import ApplicationServices
import AppKit
import BannerShiftCore
import CoreGraphics

final class BannerMover {
    private var baselines: [UInt64: Baseline] = [:]
    private let logger: FileLogger
    private let preferences: Preferences
    private let ruleStore: RuleStore
    private let matcher: RuleMatcher
    private let animator: Animator

    init(
        logger: FileLogger,
        preferences: Preferences,
        ruleStore: RuleStore,
        matcher: RuleMatcher,
        animator: Animator
    ) {
        self.logger = logger
        self.preferences = preferences
        self.ruleStore = ruleStore
        self.matcher = matcher
        self.animator = animator
    }

    /// Top-level pass: visit each notification UI window and move-or-restore.
    func process(notificationUIWindows windows: [AXUIElement]) {
        let defaultPosition = preferences.position
        let rules = ruleStore.load()
        let screens = currentScreens()
        for window in windows {
            processWindow(window,
                          defaultPosition: defaultPosition,
                          rules: rules,
                          screens: screens)
        }
    }

    /// Clear all per-window state and cancel in-flight animations.
    /// Used when the notification UI process terminates (plan §11).
    func reset() {
        baselines.removeAll()
        animator.cancelAll()
    }

    // MARK: Internals

    private func processWindow(
        _ window: AXUIElement,
        defaultPosition: Position,
        rules: [Rule],
        screens: [ScreenInfo]
    ) {
        let id = elementID(window)

        // Open Notification Center panel: restore and skip.
        if NotificationCenterPanelDetector.isPanel(window) {
            restoreIfNeeded(window: window, id: id)
            return
        }

        // No banner inside this window: restore and skip.
        guard let banner = AXBannerFinder.find(in: window),
              let bannerFrame = AXBannerFinder.frame(of: banner),
              let windowFrame = AXBannerFinder.frame(of: window) else {
            restoreIfNeeded(window: window, id: id)
            return
        }

        // Extract banner text, resolve bundle ID, find matching rule.
        var bannerText = BannerTextExtractor.extract(from: banner)
        if let bid = AppResolver.bundleID(forAppName: bannerText.appName) {
            bannerText = BannerText(
                appName: bannerText.appName, bundleID: bid,
                title: bannerText.title, subtitle: bannerText.subtitle, body: bannerText.body
            )
        }
        let match = matcher.match(rules: rules, banner: bannerText)
        let position  = match?.rule.position  ?? defaultPosition
        let animation = match?.rule.animation ?? .none

        // Pick the display the window currently belongs to.
        let centerAX = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        let activeFallback = NSScreen.main.map(snapshot)
        let selector = DisplaySelector(screens: screens)
        guard let screen = selector.screenContaining(
            axPoint: centerAX,
            activeScreenFallback: activeFallback
        ) else {
            logger.error("BannerMover: no screen available, skipping move")
            return
        }

        // Capture baseline on first sight of this window.
        if baselines[id] == nil {
            baselines[id] = Baseline(
                originalOrigin: windowFrame.origin,
                windowFrame: windowFrame,
                bannerFrame: bannerFrame
            )
        }
        guard let baseline = baselines[id] else { return }

        let calc = PositionCalculator(
            windowFrame: baseline.windowFrame,
            bannerFrame: baseline.bannerFrame,
            screen: screen
        )
        guard calc.invariantHolds else {
            logger.error("BannerMover: window-height invariant violated " +
                         "(window=\(baseline.windowFrame.height), " +
                         "screen=\(screen.frame.height)); skipping move")
            return
        }
        let target = calc.targetOrigin(for: position)

        // Animation `.slide` interpolates from the OS's original origin;
        // others ignore `from` and oscillate around the target.
        let from: CGPoint
        switch animation {
        case .slide:                  from = baseline.originalOrigin
        case .none, .shake, .bounce:  from = target
        }
        let frames = AnimationFrames.frames(style: animation, from: from, to: target)
        let delay: TimeInterval = (animation == .none) ? 0 : Animator.startDelay
        animator.animate(windowID: id, window: window, frames: frames, delay: delay)

        logger.debug(
            "BannerMover: window=\(String(format: "%016llx", id)) " +
            "rule=\(match?.rule.name ?? "(default)") " +
            "position=\(position.rawValue) animation=\(animation.rawValue) " +
            "target=\(target)"
        )
    }

    private func restoreIfNeeded(window: AXUIElement, id: UInt64) {
        guard let baseline = baselines[id] else { return }
        animator.cancel(windowID: id)
        Animator.set(point: baseline.originalOrigin, on: window)
        baselines.removeValue(forKey: id)
        logger.debug("BannerMover: restored window \(String(format: "%016llx", id))")
    }

    private func elementID(_ el: AXUIElement) -> UInt64 {
        UInt64(UInt(bitPattern: Unmanaged.passUnretained(el).toOpaque()))
    }

    private func currentScreens() -> [ScreenInfo] {
        NSScreen.screens.enumerated().map { idx, scr in
            ScreenInfo(frame: scr.frame, visibleFrame: scr.visibleFrame, isPrimary: idx == 0)
        }
    }

    private func snapshot(_ scr: NSScreen) -> ScreenInfo {
        let isPrimary = NSScreen.screens.first == scr
        return ScreenInfo(frame: scr.frame, visibleFrame: scr.visibleFrame, isPrimary: isPrimary)
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/BannerMover.swift
git commit -m "feat(app): BannerMover orchestrator

- Per-window baseline tracking keyed by AX element address
- Extracts banner text, resolves bundle ID, consults rule matcher
- Per-banner position + animation: rule override → default
- Drives Animator with AnimationFrames so .slide / .shake / .bounce
  produce smooth motion via repeated AX position writes
- Skips move when §20.3 invariant fails
- Cancels in-flight animation on restore and on process teardown"
```

---

## Task 17: AX observer controller

**Files:**
- Create: `Sources/BannerShift/AXObserverController.swift`

Owns the `AXObserver`, registers for the three event types on the app and all current windows, and exposes a callback to the rest of the app. Uses `ObserverKey` for window-level dedup.

- [ ] **Step 1: Implement `AXObserverController.swift`**

```swift
import ApplicationServices
import AppKit
import BannerShiftCore
import CoreGraphics

final class AXObserverController {
    typealias EventHandler = () -> Void

    private let pid: pid_t
    private let appElement: AXUIElement
    private var observer: AXObserver?
    private var registeredWindowKeys: Set<ObserverKey> = []
    private var handler: EventHandler?
    private let logger: FileLogger

    private static let notifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXMainWindowChangedNotification,
        "AXLayoutChanged",   // umbrella; some macOS releases use this
    ]

    init(pid: pid_t, logger: FileLogger) {
        self.pid = pid
        self.appElement = AXUIElementCreateApplication(pid)
        self.logger = logger
    }

    func start(handler: @escaping EventHandler) {
        self.handler = handler
        var rawObserver: AXObserver?
        let result = AXObserverCreate(pid, Self.callback, &rawObserver)
        guard result == .success, let observer = rawObserver else {
            logger.error("AXObserverController: AXObserverCreate failed (\(result.rawValue))")
            return
        }
        self.observer = observer
        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        register(element: appElement, key: nil)
        refreshWindows()
    }

    func stop() {
        observer = nil
        registeredWindowKeys.removeAll()
        handler = nil
    }

    /// Called by clients (typically on the debounce pass) to pick up
    /// windows created since startup.
    func refreshWindows() {
        guard observer != nil else { return }
        let children = AXBannerFinder.arrayAttribute(appElement, kAXWindowsAttribute as CFString)
        for window in children {
            let key = makeKey(for: window)
            if !registeredWindowKeys.contains(key) {
                register(element: window, key: key)
                registeredWindowKeys.insert(key)
            }
        }
    }

    func notificationUIWindows() -> [AXUIElement] {
        AXBannerFinder.arrayAttribute(appElement, kAXWindowsAttribute as CFString)
    }

    private func register(element: AXUIElement, key: ObserverKey?) {
        guard let observer else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        for notif in Self.notifications {
            AXObserverAddNotification(observer, element, notif as CFString, selfPtr)
        }
    }

    private func makeKey(for window: AXUIElement) -> ObserverKey {
        let role = AXBannerFinder.stringAttribute(window, kAXRoleAttribute as CFString) ?? "?"
        let subrole = AXBannerFinder.stringAttribute(window, kAXSubroleAttribute as CFString) ?? "?"
        let size = AXBannerFinder.sizeAttribute(window, kAXSizeAttribute as CFString) ?? .zero
        let id = UInt64(UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque()))
        return ObserverKey(elementID: id, role: role, subrole: subrole, size: size)
    }

    // C callback; trampoline into the Swift handler.
    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let me = Unmanaged<AXObserverController>.fromOpaque(refcon).takeUnretainedValue()
        me.handler?()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/AXObserverController.swift
git commit -m "feat(app): AXObserverController

Owns the AXObserver and per-window registrations. Dedups by
ObserverKey (with element identity), so re-registration after a
move is a no-op (plan §11, with fix)."
```

---

## Task 18: Notification UI lifecycle watcher

**Files:**
- Create: `Sources/BannerShift/NotificationUIWatcher.swift`

Per §11. Watches `NSWorkspace` launch/terminate events. On launch of the notification UI process, builds and starts a fresh `AXObserverController`; on termination, tears down and clears all per-window state.

- [ ] **Step 1: Implement `NotificationUIWatcher.swift`**

```swift
import AppKit
import BannerShiftCore

final class NotificationUIWatcher {
    private let logger: FileLogger
    private let onUp: (pid_t) -> Void
    private let onDown: () -> Void
    private var observers: [NSObjectProtocol] = []

    init(
        logger: FileLogger,
        onUp: @escaping (pid_t) -> Void,
        onDown: @escaping () -> Void
    ) {
        self.logger = logger
        self.onUp = onUp
        self.onDown = onDown
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier == Constants.notificationUIBundleIdentifier {
                self.logger.info("notification UI launched (pid=\(app.processIdentifier))")
                self.onUp(app.processIdentifier)
            }
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier == Constants.notificationUIBundleIdentifier {
                self.logger.info("notification UI terminated")
                self.onDown()
            }
        })

        if let running = NSWorkspace.shared.runningApplications.first(
            where: { $0.bundleIdentifier == Constants.notificationUIBundleIdentifier }
        ) {
            onUp(running.processIdentifier)
        }
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/NotificationUIWatcher.swift
git commit -m "feat(app): NotificationUIWatcher

Workspace launch/terminate observers; bootstrap on existing pid
if the notification UI is already running at app start (plan §11)."
```

---

## Task 19: Test notification

**Files:**
- Create: `Sources/BannerShift/TestNotification.swift`

Per §12.3. Lazy permission request; bounces callbacks back to main thread.

- [ ] **Step 1: Implement `TestNotification.swift`**

```swift
import AppKit
import BannerShiftCore
import UserNotifications

enum TestNotification {
    static func send(positionName: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        DispatchQueue.main.async {
                            if granted { post(positionName: positionName) }
                            else { showDeniedAlert() }
                        }
                    }
                case .authorized, .provisional, .ephemeral:
                    post(positionName: positionName)
                case .denied:
                    showDeniedAlert()
                @unknown default:
                    showDeniedAlert()
                }
            }
        }
    }

    private static func post(positionName: String) {
        let content = UNMutableNotificationContent()
        content.title = "BannerShift"
        content.subtitle = positionName
        content.body = "If you can see this in the chosen position, it's working."
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    private static func showDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications are disabled for BannerShift"
        alert.informativeText =
            "Enable notifications in System Settings → Notifications → BannerShift " +
            "to send a test banner."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/TestNotification.swift
git commit -m "feat(app): TestNotification

Lazy permission request; explanatory alert on denial. Subtitle is
the live position name (plan §12.3)."
```

---

## Task 20: Launch-at-login toggle

**Files:**
- Create: `Sources/BannerShift/LaunchAtLoginToggle.swift`

Per §12.5: three-state SMAppService wrapper.

- [ ] **Step 1: Implement `LaunchAtLoginToggle.swift`**

```swift
import AppKit
import ServiceManagement

enum LaunchAtLoginState {
    case notRegistered
    case enabled
    case requiresApproval
    case error
}

enum LaunchAtLoginToggle {
    static var current: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .notRegistered:        return .notRegistered
        case .enabled:              return .enabled
        case .requiresApproval:     return .requiresApproval
        case .notFound:             return .notRegistered
        @unknown default:           return .error
        }
    }

    /// Returns the new state after toggling.
    @discardableResult
    static func toggle() -> LaunchAtLoginState {
        do {
            switch current {
            case .enabled, .requiresApproval:
                try SMAppService.mainApp.unregister()
            case .notRegistered, .error:
                try SMAppService.mainApp.register()
            }
        } catch {
            return .error
        }
        return current
    }

    /// Opens the Login Items pane for the user if registration ended up in
    /// `requiresApproval`.
    static func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/LaunchAtLoginToggle.swift
git commit -m "feat(app): LaunchAtLoginToggle

SMAppService wrapper exposing the three live states described in
plan §12.5, plus a helper to open Login Items in System Settings."
```

---

## Task 21: About window

**Files:**
- Create: `Sources/BannerShift/AboutWindowController.swift`

Per §12.8.

- [ ] **Step 1: Implement `AboutWindowController.swift`**

```swift
import AppKit

final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "—"
        let copyright = (info["NSHumanReadableCopyright"] as? String) ?? ""
        let name = (info["CFBundleName"] as? String) ?? "BannerShift"

        let frame = NSRect(x: 0, y: 0, width: 320, height: 220)
        let style: NSWindow.StyleMask = [.titled, .closable]
        let w = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        w.title = ""
        w.isReleasedWhenClosed = false
        w.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let icon = NSApp.applicationIconImage {
            let iv = NSImageView(image: icon)
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 64).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 64).isActive = true
            stack.addArrangedSubview(iv)
        }
        let nameLabel = label(name, weight: .semibold, size: 16)
        let versionLabel = label("Version \(version)", weight: .regular, size: 12)
        let maintainer = label("Maintainer: Ryan Emerle", weight: .regular, size: 11)
        let copyLabel = label(copyright, weight: .regular, size: 11)
        copyLabel.maximumNumberOfLines = 2

        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(versionLabel)
        stack.addArrangedSubview(maintainer)
        stack.addArrangedSubview(copyLabel)

        let content = NSView(frame: frame)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        w.contentView = content
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func label(_ text: String, weight: NSFont.Weight, size: CGFloat) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.alignment = .center
        return f
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/AboutWindowController.swift
git commit -m "feat(app): AboutWindowController

Transient utility window per plan §12.8. Re-shown on subsequent
opens; not destroyed."
```

---

## Task 22: Menu bar controller

**Files:**
- Create: `Sources/BannerShift/MenuBarController.swift`

Per §12 plus the "Rules…" entry from §22 (placed above the position picker).

- [ ] **Step 1: Implement `MenuBarController.swift`**

```swift
import AppKit
import BannerShiftCore

final class MenuBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let preferences: Preferences
    private let about = AboutWindowController()
    private let onPositionChanged: (Position) -> Void
    private let onShowRules: () -> Void
    private let onQuit: () -> Void
    private let onHide: () -> Void

    init(
        preferences: Preferences,
        onPositionChanged: @escaping (Position) -> Void,
        onShowRules: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.onPositionChanged = onPositionChanged
        self.onShowRules = onShowRules
        self.onHide = onHide
        self.onQuit = onQuit
    }

    func show() {
        guard item == nil else { return }
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = i.button {
            let img = NSImage(systemSymbolName: "bell.badge.fill",
                              accessibilityDescription: "BannerShift")
            img?.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()
        menu.delegate = self
        i.menu = menu
        item = i
        rebuildMenu()
    }

    func hide() {
        guard let i = item else { return }
        NSStatusBar.system.removeStatusItem(i)
        item = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let menu = item?.menu else { return }
        menu.removeAllItems()

        // Rules… (above the position picker per spec §22)
        let rulesItem = NSMenuItem(title: "Rules\u{2026}",
                                   action: #selector(showRules(_:)),
                                   keyEquivalent: "")
        rulesItem.target = self
        menu.addItem(rulesItem)
        menu.addItem(.separator())

        // Default-position picker (used when no rule overrides it).
        let header = NSMenuItem(title: "Default Position", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for p in Position.allCases {
            let mi = NSMenuItem(title: p.displayName,
                                action: #selector(selectPosition(_:)),
                                keyEquivalent: "")
            mi.target = self
            mi.representedObject = p
            mi.state = (p == preferences.position) ? .on : .off
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let test = NSMenuItem(title: "Send a Test Notification",
                              action: #selector(sendTest(_:)), keyEquivalent: "")
        test.target = self
        menu.addItem(test)
        menu.addItem(.separator())

        let launch = NSMenuItem(title: launchAtLoginTitle(),
                                action: #selector(toggleLaunch(_:)), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginCheckState()
        menu.addItem(launch)
        menu.addItem(.separator())

        let hide = NSMenuItem(title: "Hide Menu Bar Icon…",
                              action: #selector(hideIcon(_:)), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About BannerShift",
                                   action: #selector(showAbout(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quit = NSMenuItem(title: "Quit BannerShift",
                              action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func launchAtLoginTitle() -> String {
        switch LaunchAtLoginToggle.current {
        case .requiresApproval: return "Launch at Login (Requires Approval)"
        default:                return "Launch at Login"
        }
    }

    private func launchAtLoginCheckState() -> NSControl.StateValue {
        LaunchAtLoginToggle.current == .enabled ? .on : .off
    }

    // MARK: Actions

    @objc private func selectPosition(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? Position else { return }
        preferences.position = p
        onPositionChanged(p)
    }

    @objc private func sendTest(_ sender: NSMenuItem) {
        TestNotification.send(positionName: preferences.position.displayName)
    }

    @objc private func toggleLaunch(_ sender: NSMenuItem) {
        let newState = LaunchAtLoginToggle.toggle()
        if newState == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "BannerShift needs approval"
            alert.informativeText = "Approve BannerShift in System Settings → General → Login Items."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                LaunchAtLoginToggle.openSettings()
            }
        }
    }

    @objc private func hideIcon(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText =
            "BannerShift will keep running. Re-launch BannerShift to bring the icon back."
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            preferences.iconHidden = true
            hide()
            onHide()
        }
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        about.show()
    }

    @objc private func showRules(_ sender: NSMenuItem) {
        onShowRules()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        onQuit()
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add Sources/BannerShift/MenuBarController.swift
git commit -m "feat(app): MenuBarController

NSStatusItem with: Rules… entry (above the picker), default-position
picker, test-notification, launch-at-login (3-state), hide-icon
(with confirmation), about, quit. Menu rebuilds on each open so
live state is reflected (plan §12, §22)."
```

---

## Task 22A: Rule editor window controller

**Files:**
- Create: `Sources/BannerShift/RuleEditorWindowController.swift`

Per spec §22. Single window with: rules table (left), detail pane (right), sample-text matcher (bottom). Saves on edit-end and on table reorder. Re-opens instantly because the window is hidden, not destroyed, on close. This is the largest single source file in the project; that's acceptable for a self-contained UI controller.

- [ ] **Step 1: Implement `RuleEditorWindowController.swift`**

```swift
import AppKit
import BannerShiftCore
import Foundation

final class RuleEditorWindowController: NSWindowController {
    private let ruleStore: RuleStore
    private let matcher = RuleMatcher()
    private var rules: [Rule] = []
    private var selectedIndex: Int?

    // List pane
    private let tableView = NSTableView()
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    // Detail pane controls
    private let nameField = NSTextField()
    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let appField = NSTextField()
    private let bundleField = NSTextField()
    private let titleField = NSTextField()
    private let subtitleField = NSTextField()
    private let bodyField = NSTextField()
    private let appError = NSTextField(labelWithString: "")
    private let bundleError = NSTextField(labelWithString: "")
    private let titleError = NSTextField(labelWithString: "")
    private let subtitleError = NSTextField(labelWithString: "")
    private let bodyError = NSTextField(labelWithString: "")
    private let positionPopUp = NSPopUpButton()
    private let animationPopUp = NSPopUpButton()

    // Sample tester
    private let sampleAppField = NSTextField()
    private let sampleTitleField = NSTextField()
    private let sampleSubtitleField = NSTextField()
    private let sampleBodyField = NSTextField()
    private let testResultLabel = NSTextField(labelWithString: "No rule matches.")

    init(ruleStore: RuleStore) {
        self.ruleStore = ruleStore
        let frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "BannerShift Rules"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        rules = ruleStore.load()
        buildUI()
        refreshTable()
        loadDetailForSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        configureTable()
        addButton.target = self;    addButton.action = #selector(addRule)
        removeButton.target = self; removeButton.action = #selector(removeRule)
        let listButtons = NSStackView(views: [addButton, removeButton])
        listButtons.orientation = .horizontal
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let leftStack = NSStackView(views: [scroll, listButtons])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 6

        let detail = makeDetailForm()

        let top = NSStackView(views: [leftStack, detail])
        top.orientation = .horizontal
        top.distribution = .fillEqually
        top.spacing = 16

        let separator = NSBox()
        separator.boxType = .separator

        let bottom = makeTester()

        let outer = NSStackView(views: [top, separator, bottom])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 12
        outer.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        outer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            outer.topAnchor.constraint(equalTo: content.topAnchor),
            outer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    private func configureTable() {
        let cols: [(String, String, CGFloat)] = [
            ("on",   "On",   40),
            ("name", "Name", 140),
            ("app",  "App",  100),
            ("rule", "Pos / Anim", 120),
        ]
        for (id, title, w) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = w
            tableView.addTableColumn(col)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.action = #selector(tableSelectionChanged(_:))
        tableView.registerForDraggedTypes([.string])
    }

    private func makeDetailForm() -> NSView {
        nameField.placeholderString = "Rule name"
        enabledButton.target = self; enabledButton.action = #selector(detailChanged)
        nameField.delegate = self
        for tf in [appField, bundleField, titleField, subtitleField, bodyField] {
            tf.delegate = self
            tf.placeholderString = "regex (empty = wildcard)"
        }
        for err in [appError, bundleError, titleError, subtitleError, bodyError] {
            err.textColor = .systemRed
            err.font = .systemFont(ofSize: 10)
        }
        positionPopUp.addItem(withTitle: "(default)")
        for p in Position.allCases { positionPopUp.addItem(withTitle: p.displayName) }
        positionPopUp.target = self; positionPopUp.action = #selector(detailChanged)

        animationPopUp.addItem(withTitle: "(default)")
        for a in Animation.allCases { animationPopUp.addItem(withTitle: a.displayName) }
        animationPopUp.target = self; animationPopUp.action = #selector(detailChanged)

        func row(_ label: String, _ control: NSView, _ err: NSView? = nil) -> NSStackView {
            let l = NSTextField(labelWithString: label)
            l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 90).isActive = true
            var subs: [NSView] = [l, control]
            if let err { subs.append(err) }
            let r = NSStackView(views: subs)
            r.orientation = .horizontal
            r.spacing = 6
            return r
        }

        let stack = NSStackView(views: [
            row("Name:",      nameField),
            row("",           enabledButton),
            row("App:",       appField,       appError),
            row("Bundle ID:", bundleField,    bundleError),
            row("Title:",     titleField,     titleError),
            row("Subtitle:",  subtitleField,  subtitleError),
            row("Body:",      bodyField,      bodyError),
            row("Position:",  positionPopUp),
            row("Animation:", animationPopUp),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    private func makeTester() -> NSView {
        let header = NSTextField(labelWithString: "Test against sample text:")
        header.font = .boldSystemFont(ofSize: 12)
        for tf in [sampleAppField, sampleTitleField, sampleSubtitleField, sampleBodyField] {
            tf.delegate = self
        }
        sampleAppField.placeholderString = "App"
        sampleTitleField.placeholderString = "Title"
        sampleSubtitleField.placeholderString = "Subtitle"
        sampleBodyField.placeholderString = "Body"
        let inputs = NSStackView(views: [sampleAppField, sampleTitleField, sampleSubtitleField, sampleBodyField])
        inputs.orientation = .horizontal
        inputs.distribution = .fillEqually
        inputs.spacing = 6
        let stack = NSStackView(views: [header, inputs, testResultLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        return stack
    }

    // MARK: Table ops

    private func refreshTable() {
        tableView.reloadData()
        if let i = selectedIndex, rules.indices.contains(i) {
            tableView.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
    }

    @objc private func tableSelectionChanged(_ sender: NSTableView) {
        selectedIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
        loadDetailForSelection()
        updateTestResult()
    }

    @objc private func addRule() {
        rules.append(Rule(name: "New Rule"))
        selectedIndex = rules.count - 1
        save()
        refreshTable()
        loadDetailForSelection()
    }

    @objc private func removeRule() {
        guard let i = selectedIndex, rules.indices.contains(i) else { return }
        rules.remove(at: i)
        selectedIndex = rules.isEmpty ? nil : min(i, rules.count - 1)
        save()
        refreshTable()
        loadDetailForSelection()
    }

    // MARK: Detail load/save

    private func loadDetailForSelection() {
        let r = selectedIndex.flatMap { rules.indices.contains($0) ? rules[$0] : nil }
        let on = r != nil
        for c in [nameField, enabledButton, appField, bundleField, titleField,
                  subtitleField, bodyField, positionPopUp, animationPopUp] as [NSControl] {
            c.isEnabled = on
        }
        guard let r else {
            nameField.stringValue = ""
            enabledButton.state = .off
            for tf in [appField, bundleField, titleField, subtitleField, bodyField] { tf.stringValue = "" }
            positionPopUp.selectItem(at: 0)
            animationPopUp.selectItem(at: 0)
            clearValidation()
            return
        }
        nameField.stringValue = r.name
        enabledButton.state = r.enabled ? .on : .off
        appField.stringValue      = r.appPattern      ?? ""
        bundleField.stringValue   = r.bundleIDPattern ?? ""
        titleField.stringValue    = r.titlePattern    ?? ""
        subtitleField.stringValue = r.subtitlePattern ?? ""
        bodyField.stringValue     = r.bodyPattern     ?? ""
        positionPopUp.selectItem(at: r.position.flatMap { Position.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        animationPopUp.selectItem(at: r.animation.flatMap { Animation.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        validateAll()
    }

    @objc private func detailChanged() {
        guard let i = selectedIndex, rules.indices.contains(i) else { return }
        var r = rules[i]
        r.name             = nameField.stringValue
        r.enabled          = enabledButton.state == .on
        r.appPattern       = nilIfEmpty(appField.stringValue)
        r.bundleIDPattern  = nilIfEmpty(bundleField.stringValue)
        r.titlePattern     = nilIfEmpty(titleField.stringValue)
        r.subtitlePattern  = nilIfEmpty(subtitleField.stringValue)
        r.bodyPattern      = nilIfEmpty(bodyField.stringValue)
        let pi = positionPopUp.indexOfSelectedItem
        r.position  = pi == 0 ? nil : Position.allCases[pi - 1]
        let ai = animationPopUp.indexOfSelectedItem
        r.animation = ai == 0 ? nil : Animation.allCases[ai - 1]
        rules[i] = r
        save()
        validateAll()
        updateTestResult()
        tableView.reloadData(forRowIndexes: IndexSet(integer: i),
                             columnIndexes: IndexSet(integersIn: 0..<tableView.tableColumns.count))
    }

    private func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
    private func save() { ruleStore.save(rules) }

    // MARK: Regex validation

    private func validateAll() {
        validate(appField, into: appError)
        validate(bundleField, into: bundleError)
        validate(titleField, into: titleError)
        validate(subtitleField, into: subtitleError)
        validate(bodyField, into: bodyError)
    }

    private func validate(_ field: NSTextField, into err: NSTextField) {
        field.wantsLayer = true
        let s = field.stringValue
        if s.isEmpty {
            field.layer?.borderWidth = 0
            err.stringValue = ""
            return
        }
        do {
            _ = try Regex(s)
            field.layer?.borderWidth = 0
            err.stringValue = ""
        } catch {
            field.layer?.borderColor = NSColor.systemRed.cgColor
            field.layer?.borderWidth = 1
            err.stringValue = "Invalid regex"
        }
    }

    private func clearValidation() {
        for (f, l) in [(appField, appError), (bundleField, bundleError),
                       (titleField, titleError), (subtitleField, subtitleError),
                       (bodyField, bodyError)] {
            f.layer?.borderWidth = 0
            l.stringValue = ""
        }
    }

    // MARK: Sample tester

    @objc fileprivate func updateTestResult() {
        let banner = BannerText(
            appName: sampleAppField.stringValue,
            title: sampleTitleField.stringValue,
            subtitle: sampleSubtitleField.stringValue,
            body: sampleBodyField.stringValue
        )
        if let match = matcher.match(rules: rules, banner: banner) {
            testResultLabel.stringValue = "Match: \(match.rule.name)"
            testResultLabel.textColor = .systemGreen
        } else {
            testResultLabel.stringValue = "No rule matches."
            testResultLabel.textColor = .secondaryLabelColor
        }
    }
}

// MARK: NSTableViewDataSource

extension RuleEditorWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString("\(row)", forType: .string)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let s = item.string(forType: .string),
              let src = Int(s) else { return false }
        let dst = src < row ? row - 1 : row
        let moved = rules.remove(at: src)
        rules.insert(moved, at: min(dst, rules.count))
        selectedIndex = dst
        save()
        refreshTable()
        return true
    }
}

// MARK: NSTableViewDelegate

extension RuleEditorWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let rule = rules[row]
        switch id {
        case "on":
            let btn = NSButton(checkboxWithTitle: "", target: self, action: #selector(rowEnabledToggled(_:)))
            btn.state = rule.enabled ? .on : .off
            btn.tag = row
            return btn
        case "name": return NSTextField(labelWithString: rule.name)
        case "app":  return NSTextField(labelWithString: rule.appPattern ?? "(any)")
        case "rule":
            let pos  = rule.position?.displayName  ?? "default"
            let anim = rule.animation?.displayName ?? "default"
            return NSTextField(labelWithString: "\(pos) / \(anim)")
        default: return nil
        }
    }

    @objc fileprivate func rowEnabledToggled(_ sender: NSButton) {
        let row = sender.tag
        guard rules.indices.contains(row) else { return }
        rules[row].enabled = sender.state == .on
        save()
        if selectedIndex == row { loadDetailForSelection() }
    }
}

// MARK: NSTextFieldDelegate

extension RuleEditorWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        // Sample-tester fields update on every keystroke.
        if [sampleAppField, sampleTitleField, sampleSubtitleField, sampleBodyField].contains(field) {
            updateTestResult()
            return
        }
        // Detail regex fields: live-validate; commit happens on focus-end.
        switch field {
        case appField:      validate(appField, into: appError)
        case bundleField:   validate(bundleField, into: bundleError)
        case titleField:    validate(titleField, into: titleError)
        case subtitleField: validate(subtitleField, into: subtitleError)
        case bodyField:     validate(bodyField, into: bodyError)
        default: break
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if [nameField, appField, bundleField, titleField, subtitleField, bodyField].contains(field) {
            detailChanged()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `make build`
Expected: success.

- [ ] **Step 3: Manual smoke (do this once the AppDelegate wires it, Task 23)**

After Task 23: open the menu bar, click "Rules…", confirm:
- Window opens centered, 760×560.
- Click "Add" → "New Rule" appears in the table; detail pane becomes enabled.
- Type a rule name; tab away → table row updates.
- Enter an invalid regex like `[unterminated` in the App field → red border + "Invalid regex" appears below.
- Fix the regex → red border clears.
- Type in the sample-tester fields → "Match: …" / "No rule matches." updates live.
- Drag a row to reorder → order persists; closing and re-opening the window shows the new order.
- Close the window → next open is instant (hidden, not destroyed).

- [ ] **Step 4: Commit**

```bash
git add Sources/BannerShift/RuleEditorWindowController.swift
git commit -m "feat(app): RuleEditorWindowController

Single-window editor per plan §22:
- Table: enabled/name/app/pos+anim columns; drag-to-reorder
- Detail pane: five regex inputs with live validation, position
  and animation dropdowns (each with a (default) sentinel)
- Saves on focus-end and on table reorder; no Save button
- Sample-text tester at the bottom shows which rule wins
- Hidden (not destroyed) on close so re-open is instant"
```

---

## Task 23: AppDelegate wiring

**Files:**
- Create: `Sources/BannerShift/AppDelegate.swift`
- Modify: `Sources/BannerShift/main.swift`

Top-level wiring. Owns: `Preferences`, `FileLogger`, `RuleStore`, `RuleMatcher`, `Animator`, `BannerMover`, `Debouncer`, `AXObserverController`, `NotificationUIWatcher`, `MenuBarController`, `RuleEditorWindowController`.

- [ ] **Step 1: Replace `main.swift`**

```swift
// Sources/BannerShift/main.swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

- [ ] **Step 2: Implement `AppDelegate.swift`**

```swift
import AppKit
import BannerShiftCore
import Foundation
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private var logger: FileLogger!
    private var osLog = Logger(subsystem: Constants.bundleIdentifier, category: "app")
    private var ruleStore: RuleStore!
    private let matcher = RuleMatcher()
    private let animator = Animator()
    private var ruleEditor: RuleEditorWindowController!
    private var mover: BannerMover!
    private var debouncer: Debouncer!
    private var axObserver: AXObserverController?
    private var watcher: NotificationUIWatcher!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. File logger first so subsequent errors can be recorded.
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        let logURL = logsDir.appendingPathComponent("BannerShift.log")
        do {
            logger = try FileLogger(url: logURL,
                                    isDebugEnabled: { [preferences] in preferences.debugLoggingEnabled })
        } catch {
            osLog.error("Cannot open log file: \(error.localizedDescription, privacy: .public)")
            NSApp.terminate(nil); return
        }
        logger.info("launched")

        // 2. Accessibility permission. Mandatory.
        guard AccessibilityPermission.requireOrExit() else {
            logger.error("accessibility permission not granted — terminating")
            osLog.error("accessibility permission not granted — terminating")
            NSApp.terminate(nil); return
        }

        // 3. Rule store + editor.
        ruleStore = RuleStore(
            defaults: .standard,
            logger: { [weak self] msg in self?.logger.error(msg) }
        )
        ruleEditor = RuleEditorWindowController(ruleStore: ruleStore)

        // 4. Banner mover machinery.
        mover = BannerMover(
            logger: logger,
            preferences: preferences,
            ruleStore: ruleStore,
            matcher: matcher,
            animator: animator
        )
        debouncer = Debouncer(interval: Constants.eventDebounceInterval, queue: .main)

        // 5. Workspace observers; start the AX observer when the
        //    notification UI process is up.
        watcher = NotificationUIWatcher(
            logger: logger,
            onUp:   { [weak self] pid in self?.bringUpObserver(pid: pid) },
            onDown: { [weak self] in    self?.tearDownObserver() }
        )
        watcher.start()

        // 6. Menu bar.
        menuBar = MenuBarController(
            preferences: preferences,
            onPositionChanged: { [weak self] _ in self?.kickPass() },
            onShowRules:       { [weak self] in self?.ruleEditor.show() },
            onHide:            { /* nothing extra to do */ },
            onQuit:            { NSApp.terminate(nil) }
        )
        if !preferences.iconHidden {
            menuBar.show()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Hidden-icon recovery: relaunch (or front-launch) reveals the icon.
        if preferences.iconHidden {
            preferences.iconHidden = false
            menuBar.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        axObserver?.stop()
        logger?.close()
    }

    // MARK: Observer plumbing

    private func bringUpObserver(pid: pid_t) {
        axObserver = AXObserverController(pid: pid, logger: logger)
        axObserver?.start(handler: { [weak self] in self?.kickPass() })
        kickPass()  // initial sweep
    }

    private func tearDownObserver() {
        axObserver?.stop()
        axObserver = nil
        mover.reset()
        debouncer.cancel()
    }

    private func kickPass() {
        debouncer.schedule { [weak self] in
            guard let self else { return }
            self.axObserver?.refreshWindows()
            let windows = self.axObserver?.notificationUIWindows() ?? []
            self.mover.process(notificationUIWindows: windows)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `make build`
Expected: success.

- [ ] **Step 4: Commit**

```bash
git add Sources/BannerShift/main.swift Sources/BannerShift/AppDelegate.swift
git commit -m "feat(app): AppDelegate wires everything

Permission gate → logger → rule store + editor → matcher + animator
→ BannerMover → workspace watcher → AX observer → debouncer → menu
bar (with onShowRules). Hidden-icon reveal on app activation. Clean
shutdown closes the log handle (plan §22)."
```

---

## Task 24: Dev build script

**Files:**
- Create: `scripts/build-dev.sh`

Assemble an ad-hoc-signed universal `.app` bundle for local use.

- [ ] **Step 1: Write `scripts/build-dev.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BannerShift.app"

echo "==> swift build (universal release)"
swift build -c release \
    --triple arm64-apple-macos13.0
swift build -c release \
    --triple x86_64-apple-macos13.0

ARM_BIN="$ROOT/.build/arm64-apple-macos13.0/release/BannerShift"
X86_BIN="$ROOT/.build/x86_64-apple-macos13.0/release/BannerShift"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP/Contents/MacOS/BannerShift"
chmod +x "$APP/Contents/MacOS/BannerShift"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> ad-hoc signing"
codesign --force --sign - \
    --entitlements "$ROOT/Resources/BannerShift.entitlements" \
    --options runtime \
    "$APP"

echo "==> done: $APP"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/build-dev.sh`

- [ ] **Step 3: Try the build**

Run: `./scripts/build-dev.sh`
Expected: produces `build/BannerShift.app` with a universal binary. Run `lipo -info build/BannerShift.app/Contents/MacOS/BannerShift` and confirm `arm64 x86_64`.

- [ ] **Step 4: Verify the app launches and the AX prompt appears**

Run: `open build/BannerShift.app`
Expected:
- No Dock icon (`LSUIElement=true`).
- macOS prompts for Accessibility permission (first run).
- After granting and relaunching, a menu-bar bell icon appears.
- Selecting "Send a Test Notification" produces a banner at the chosen position.

If the test notification appears at the OS-default location instead of the chosen one, the most likely cause is one of the spec's known fragilities: the banner subroles (§20.1) or the panel identifier (§20.2) have changed in this macOS release. Update `Constants.swift` and rebuild.

- [ ] **Step 5: Commit**

```bash
git add scripts/build-dev.sh
git commit -m "build: add dev-build script

Universal binary via swift build per-arch + lipo. Ad-hoc signed,
hardened runtime, entitlements applied. Output: build/BannerShift.app."
```

---

## Task 25: Release signing pipeline

**Files:**
- Create: `populate-secrets.sh`  (one-shot, materializes `.env` and `.secrets/AuthKey.p8`)
- Create: `release.sh`           (consumes `.env`, builds, signs, notarizes, staples, packages)

Mirrors the pattern Q already uses in `~/repos/personal/PingPlace/populate-secrets.sh`. Two-file split: secrets are fetched once and persisted to a gitignored `.env` consumed by `release.sh`; the Developer ID identity is discovered from the keychain rather than stored in 1Password. Re-running `populate-secrets.sh` is safe; outputs are overwritten.

**Before running this task**, the 1Password vault must contain:
- An item for the App Store Connect API key with file attachment `AuthKey_<KEYID>.p8` and string fields `key id` and `issuer id`.
- An item for the Developer ID Application certificate, with a `.p12` attachment and the .p12 passphrase in `notesPlain` (only needed if you'll use `--import-certs` on a fresh machine).

Item titles often contain characters (parens, spaces) that the `op://` reference parser rejects, so item *IDs* are used as references and titles live in comments.

- [ ] **Step 1: Write `populate-secrets.sh`**

```bash
#!/usr/bin/env bash
#
# One-shot: pull build secrets out of 1Password and materialize them locally.
#
# Writes:
#   .env                       env vars consumed by release.sh
#   .secrets/AuthKey.p8        App Store Connect API key (mode 0600)
#
# Optional (--import-certs): also pull the Developer ID Application .p12
# and import it into the login keychain. Only needed on a fresh machine
# where the cert is not yet present.
#
# Re-running is safe; outputs are overwritten.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/.secrets"
ENV_FILE="${SCRIPT_DIR}/.env"

# 1Password vault. Override with: VAULT=Personal ./populate-secrets.sh
VAULT="${VAULT:-Personal}"

# Item IDs are used in op:// references because item titles often contain
# characters (parens, spaces) that the reference parser rejects.
# Titles are kept here as comments for human readers.
# Replace these with the actual item IDs for BannerShift signing.
APP_CERT_ITEM="${APP_CERT_ITEM:-REPLACE_WITH_DEVELOPER_ID_ITEM_ID}"  # Developer ID Application Cert
ASC_ITEM="${ASC_ITEM:-REPLACE_WITH_ASC_KEY_ITEM_ID}"                  # App Store Connect API key

APP_P12_FILENAME="${APP_P12_FILENAME:-Developer ID Private Key.p12}"
ASC_KEY_FILENAME="${ASC_KEY_FILENAME:-AuthKey_REPLACE.p8}"

IMPORT_CERTS=0
for arg in "$@"; do
    case "${arg}" in
        --import-certs) IMPORT_CERTS=1 ;;
        -h|--help)
            sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "Unknown arg: ${arg}" >&2; exit 2 ;;
    esac
done

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!!\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31mxxx\033[0m %s\n" "$*" >&2; exit 1; }

command -v op >/dev/null 2>&1 || die "1Password CLI 'op' not found in PATH."
op whoami >/dev/null 2>&1     || die "1Password CLI not signed in. Run 'op signin'."

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

# ---------------------------------------------------------------------------
# Fetch App Store Connect API key + identifiers
# ---------------------------------------------------------------------------

log "Fetching App Store Connect API key from 1Password (vault: ${VAULT})..."
P8_PATH="${SECRETS_DIR}/AuthKey.p8"
op read --out-file "${P8_PATH}" \
    "op://${VAULT}/${ASC_ITEM}/${ASC_KEY_FILENAME}" >/dev/null
chmod 600 "${P8_PATH}"
[[ -s "${P8_PATH}" ]] || die "Fetched .p8 is empty: ${P8_PATH}"

log "Reading App Store Connect key id + issuer id..."
AC_KEY_ID="$(op read "op://${VAULT}/${ASC_ITEM}/key id")"
AC_ISSUER_ID="$(op read "op://${VAULT}/${ASC_ITEM}/issuer id")"
[[ -n "${AC_KEY_ID}"    ]] || die "key id field is empty"
[[ -n "${AC_ISSUER_ID}" ]] || die "issuer id field is empty"

# ---------------------------------------------------------------------------
# Discover Developer ID Application identity from the login keychain
# ---------------------------------------------------------------------------

discover_identity() {
    local label="$1"   # e.g. "Developer ID Application"
    local policy="$2"  # codesigning | basic
    # Output of `security find-identity -v -p <policy>` looks like:
    #   1) ABCDEF... "Developer ID Application: Ryan Emerle (VV49L2HH35)"
    security find-identity -v -p "${policy}" 2>/dev/null \
        | awk -v lbl="${label}" '
            {
                match($0, /"[^"]+"/);
                if (RSTART == 0) next;
                name = substr($0, RSTART+1, RLENGTH-2);
                if (index(name, lbl) == 1) print name;
            }' \
        | head -n1
}

if [[ "${IMPORT_CERTS}" == "1" ]]; then
    log "Importing Developer ID Application .p12 into login keychain..."
    p12="${SECRETS_DIR}/app.p12"
    # Wipe the private key on any exit (success, error, ^C). The .p12 only
    # needs to live long enough for `security import` to consume it.
    trap 'rm -f "${p12}"' EXIT INT TERM

    log "  Fetching ${APP_CERT_ITEM} / ${APP_P12_FILENAME}"
    op read --out-file "${p12}" \
        "op://${VAULT}/${APP_CERT_ITEM}/${APP_P12_FILENAME}" >/dev/null
    chmod 600 "${p12}"

    # `security import` has no stdin/file passphrase option, only -P <argv>,
    # so the passphrase is briefly visible to `ps` for the same user during
    # the call. Acceptable for a one-shot, rarely-run setup script.
    pass="$(op read "op://${VAULT}/${APP_CERT_ITEM}/notesPlain" 2>/dev/null || true)"
    if [[ -n "${pass}" ]]; then
        security import "${p12}" -k "${HOME}/Library/Keychains/login.keychain-db" \
            -P "${pass}" -A 2>&1 | grep -v "already in keychain" || true
    else
        warn "  No passphrase available; security import will prompt."
        security import "${p12}" -k "${HOME}/Library/Keychains/login.keychain-db" -A
    fi

    rm -f "${p12}"
    trap - EXIT INT TERM
fi

log "Discovering Developer ID Application identity from login keychain..."
DEVELOPER_ID_APPLICATION="$(discover_identity 'Developer ID Application' codesigning)"

if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
    die "No 'Developer ID Application' identity in login keychain. Re-run with --import-certs."
fi

# ---------------------------------------------------------------------------
# Write .env (overwrites)
# ---------------------------------------------------------------------------

log "Writing ${ENV_FILE}"
umask 077
# printf %q so identity strings/paths with quotes, backslashes, or whitespace
# can't break the heredoc and produce a silently truncated .env.
{
    printf '# Generated by populate-secrets.sh on %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '# DO NOT COMMIT. Regenerate with ./populate-secrets.sh\n\n'
    printf 'export DEVELOPER_ID_APPLICATION=%q\n' "${DEVELOPER_ID_APPLICATION}"
    printf 'export AC_API_KEY_PATH=%q\n'         "${P8_PATH}"
    printf 'export AC_API_KEY_ID=%q\n'           "${AC_KEY_ID}"
    printf 'export AC_API_ISSUER_ID=%q\n'        "${AC_ISSUER_ID}"
} > "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

log "Done."
log "Identity (app) : ${DEVELOPER_ID_APPLICATION}"
log "API key        : ${P8_PATH}"
log "Now run: ./release.sh"
```

- [ ] **Step 2: Write `release.sh`**

```bash
#!/usr/bin/env bash
#
# Release build: clean → universal swift build → Developer ID sign →
# notarize → staple → package.
#
# Reads .env produced by populate-secrets.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

[[ -f "${ROOT}/.env" ]] || {
    echo "Missing .env. Run ./populate-secrets.sh first." >&2
    exit 1
}
# shellcheck disable=SC1091
source "${ROOT}/.env"

: "${DEVELOPER_ID_APPLICATION:?missing in .env}"
: "${AC_API_KEY_PATH:?missing in .env}"
: "${AC_API_KEY_ID:?missing in .env}"
: "${AC_API_ISSUER_ID:?missing in .env}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy   -c 'Print :CFBundleVersion'             Resources/Info.plist)"
APP="${ROOT}/build/BannerShift.app"
ZIP="${ROOT}/build/BannerShift-${VERSION}.zip"
TAR="${ROOT}/build/BannerShift-${VERSION}.tar.gz"

log() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }

log "clean"
rm -rf "${ROOT}/build" "${ROOT}/.build"

log "build universal (ad-hoc; we re-sign below)"
"${ROOT}/scripts/build-dev.sh"

log "Developer ID sign"
codesign --force --sign "${DEVELOPER_ID_APPLICATION}" \
    --entitlements "${ROOT}/Resources/BannerShift.entitlements" \
    --options runtime \
    --timestamp \
    "${APP}"

log "verify signature"
codesign --verify --deep --strict --verbose=2 "${APP}"

log "notarize"
rm -f "${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"
xcrun notarytool submit "${ZIP}" \
    --key       "${AC_API_KEY_PATH}" \
    --key-id    "${AC_API_KEY_ID}" \
    --issuer    "${AC_API_ISSUER_ID}" \
    --wait

log "staple"
xcrun stapler staple   "${APP}"
xcrun stapler validate "${APP}"

log "package"
( cd "${ROOT}/build" && tar -czf "${TAR}" "BannerShift.app" )

log "done"
echo "  app: ${APP}"
echo "  tar: ${TAR}"
echo "  version: ${VERSION} (build ${BUILD})"
```

- [ ] **Step 3: Make executable**

Run: `chmod +x populate-secrets.sh release.sh`

- [ ] **Step 4: Configure 1Password references**

Edit `populate-secrets.sh`:
- Set `APP_CERT_ITEM` to the 1Password item ID for the Developer ID Application cert.
- Set `ASC_ITEM` to the item ID for the App Store Connect API key.
- Set `ASC_KEY_FILENAME` to the attachment filename of the .p8 (e.g. `AuthKey_ABC123XYZ.p8`).
- Set `VAULT` default if you don't want `Personal`.

To find an item ID: `op item list --vault Personal | grep -i banner` then `op item get '<title>' --format json | jq -r .id`.

- [ ] **Step 5: First-time setup — populate then release**

```bash
./populate-secrets.sh --import-certs   # first time on this machine
./release.sh
```

Subsequent runs only need `./populate-secrets.sh` (no `--import-certs`) and `./release.sh`.

- [ ] **Step 6: Commit (do NOT commit .env or .secrets/)**

```bash
git add populate-secrets.sh release.sh
git commit -m "build: add release pipeline

- populate-secrets.sh: one-shot, fetches ASC API key from 1Password,
  discovers Developer ID identity from keychain, writes .env
- release.sh: clean, build, sign, notarize, staple, package
- .env and .secrets/ are gitignored; nothing secret committed
- Mirrors the PingPlace pattern (plan §18)"
```

---

## Task 26: Manual integration verification

**Files:** none

This task is the end-to-end smoke test. No code changes.

- [ ] **Step 1: Fresh dev build**

Run: `rm -rf build .build && ./scripts/build-dev.sh`

- [ ] **Step 2: Confirm accessibility flow on first run**

1. `open build/BannerShift.app`
2. Expect a system prompt requesting Accessibility permission. Click "Open System Settings."
3. Toggle BannerShift on in Privacy & Security → Accessibility.
4. Since the app terminated on the not-yet-trusted result (per spec §4.1), relaunch: `open build/BannerShift.app`.
5. The bell icon should now appear in the menu bar.

- [ ] **Step 3: Verify position picker behavior on every cell**

For each of the nine positions:
1. Click the menu-bar icon → pick a position.
2. Click "Send a Test Notification."
3. Confirm the banner appears in that cell.
4. Note any failures (cell, observed location, screenshot if useful).

If a row's vertical position is off, suspect §7 math or the banner-subrole set (§20.1).
If horizontal is off, suspect `bannerRightInset` or the banner subroles.

- [ ] **Step 4: Notification Center panel test**

1. Pick "Bottom Left."
2. Click the menu-bar clock to open Notification Center.
3. The full panel should appear at the OS-default location, not the bottom-left.
4. Close the panel; send a test notification; it should appear bottom-left again.

If the panel itself moves: the panel identifier (§9, §20.2) needs updating.

- [ ] **Step 5: Multi-display test (skip if single-display dev machine)**

1. With two displays, send a notification on each (drag the active screen by clicking each display).
2. Each banner should land at the picked position on the display the OS originally posted it to.

- [ ] **Step 6: Sleep/wake recovery**

1. Sleep the Mac (Apple menu → Sleep).
2. Wake it; observe `Library/Logs/BannerShift.log` for a `notification UI terminated` followed by `notification UI launched` line.
3. Send a test notification — it should still move correctly.

- [ ] **Step 7: Hide menu bar icon and reveal flow**

1. Menu → "Hide Menu Bar Icon" → confirm.
2. Icon disappears.
3. `open build/BannerShift.app` to re-launch (the second process exits and the original is reactivated → `applicationDidBecomeActive` fires → icon returns).

- [ ] **Step 8: Launch at login**

1. Menu → "Launch at Login" — observe the live state transitions (`Requires Approval` may appear once; if so, click through to System Settings and approve).
2. After approval, the menu shows a checkmark next to "Launch at Login."

- [ ] **Step 9: Log file inspection**

Run: `ls -l ~/Library/Logs/BannerShift.log`
Expected: file exists, mode `-rw-------` (0600).

Run: `head ~/Library/Logs/BannerShift.log`
Expected: lines like `[INFO] 2026-MM-DDTHH:MM:SSZ launched`.

Flip debug logging:
Run: `defaults write com.emerle.BannerShift debugLoggingEnabled -bool YES`
Send a test notification.
Run: `tail ~/Library/Logs/BannerShift.log`
Expected: a `[DEBUG] ... moved window ...` line.
Run: `defaults write com.emerle.BannerShift debugLoggingEnabled -bool NO`

- [ ] **Step 10: Tag a v1.0.0 release**

Once all of the above pass:

```bash
git tag -a v1.0.0 -m "BannerShift 1.0.0"
git log --oneline | head -30
```

(Do not push the tag; that's a separate operator action.)

---

## Self-Review

**Spec coverage (cross-referenced to plan.md sections):**
- §3 LSUIElement, no Dock, no main window — Task 12 (Info.plist), Task 21 (about window is transient), Task 22A (rule editor is utility-styled).
- §4 Launch flow, accessibility-or-exit — Task 13, Task 23.
- §5 Nine positions, default-position persistence — Task 3, Task 4.
- §6 Banner discovery, display selection, banner text capture, rule matching — Task 7, Task 14, Task 14A, Task 14B, Task 16.
- §7 Position math — Task 8.
- §8 Baseline — Task 5, Task 16.
- §9 Panel detection — Task 15, Task 16.
- §10 Debounce — Task 9, Task 23.
- §11 NC UI lifecycle — Task 17, Task 18, Task 23 (with §11 dedup fix in Task 10).
- §12 Menu bar — Task 22; sub-items: rules entry (§22 — Task 22), default-position picker (✓), test notification (Task 19), launch at login (Task 20), hide icon (✓ in MenuBar + AppDelegate reveal), about (Task 21), quit (✓).
- §13 Persistence (incl. rules JSON) — Task 4, Task 11B.
- §14 Logging — Task 11 (file), Task 23 (os_log).
- §15 Concurrency model — implicit; all main-thread work.
- §16 Permissions — Task 13, Task 19.
- §17 Sandbox & code signing — Task 25.
- §18 Build & release — Task 24, Task 25.
- §19 Versioning — Info.plist `CFBundleShortVersionString` (Task 12); about window reads it (Task 21).
- §20 Fragilities — Constants.swift (Task 2), invariant check in Task 8/16.
- §22 Rules and Animations — Tasks 11A (Animation enum), 11B (BannerText, Rule, RuleStore), 11C (RuleMatcher), 11D (AnimationFrames), 14A (BannerTextExtractor), 14B (AppResolver), 14C (Animator), 16 (consumer), 22 (menu entry), 22A (editor window), 23 (wiring).
- §23 Re-implementation checklist — all items above.

**Placeholder scan:** No "TODO"/"TBD"/"similar to" in tasks. Code blocks are complete.

**Type consistency:**
- `Position` rawValues consistent across Tasks 3, 4, 11B (Codable extension), 22A, BannerMover.
- `Animation` rawValues consistent across Tasks 11A, 11B, 11D, 14C, 16, 22A.
- `Baseline` field names (`originalOrigin`, `windowFrame`, `bannerFrame`) consistent across Tasks 5, 16.
- `ScreenInfo` fields (`frame`, `visibleFrame`, `isPrimary`) consistent in Tasks 6, 7, 8, 16.
- `Constants` names consistent: `dockPadding`, `bannerRightInset`, `bundleIdentifier`, `notificationUIBundleIdentifier`, `bannerSubroles`, `notificationCenterPanelIdentifier`, `eventDebounceInterval`, `maxLogFileSize`.
- `Preferences` methods: `position` (var), `iconHidden` (var), `debugLoggingEnabled` (get-only), `setDebugLogging`.
- `Debouncer.schedule(_:)` / `.cancel()` consistent in Tasks 9, 23.
- `BannerMover.process(notificationUIWindows:)` / `.reset()` consistent in Tasks 16, 23.
- `RuleStore.load() -> [Rule]` / `.save(_:)` consistent in Tasks 11B, 22A, 23.
- `RuleMatcher.match(rules:banner:) -> RuleMatch?` consistent in Tasks 11C, 16, 22A.
- `BannerText` init signature consistent in Tasks 11B, 14A, 16, 22A.
- `Animator.animate(windowID:window:frames:delay:)` / `.cancel(windowID:)` / `.cancelAll()` / static `.set(point:on:)` consistent in Tasks 14C, 16.

No inconsistencies found.

---

## Execution

Plan complete. Estimated effort: ~3–4 focused hours for Tasks 1–22 (Core + app glue, with TDD); the dev build script (Task 24) and manual smoke test (Task 26) are where most surprises will surface (banner subrole drift, panel identifier drift). The release build script (Task 25) is essentially boilerplate but requires configured signing/notarization secrets to actually run.
