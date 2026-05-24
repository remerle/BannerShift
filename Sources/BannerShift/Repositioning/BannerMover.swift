import AppKit
import ApplicationServices
import BannerShiftCore
import CoreGraphics

/// Orchestrates one banner-repositioning pass over the notification UI
/// process's windows.
///
/// `process(notificationUIWindows:)` is the entry point, called from the
/// app delegate's debounced AX handler on the main thread; every method
/// here is main-thread-only because it reads and writes AX element
/// attributes synchronously. For each window the mover either moves the
/// contained banner to the position/animation resolved from the user's
/// rules (or the default), or restores the window to its original
/// location when there is no banner to move (e.g. the window is the
/// expanded Notification Center panel, or the banner has gone away).
///
/// `windowSnapshots` records each moved window's original geometry, keyed
/// by AX element identity (`elementID`, a pointer bit pattern). The
/// snapshot is captured on the first move so a later restore can put the
/// window back, and the map is kept bounded by dropping the entry on
/// restore and by `reset()` when the notification UI process exits and
/// every tracked element becomes invalid. The mover holds no AX observer
/// itself; it is handed the current window list each pass.
final class BannerMover {
  private var windowSnapshots: [UInt64: BannerWindowSnapshot] = [:]
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
      processWindow(
        window,
        defaultPosition: defaultPosition,
        rules: rules,
        screens: screens
      )
    }
  }

  /// Clear all per-window state and cancel in-flight animations.
  ///
  /// Called when the notification UI process (`NotificationCenter`)
  /// exits, because every AX element we were tracking is now invalid
  /// and any in-flight animation would be writing positions to
  /// dangling pointers.
  func reset() {
    windowSnapshots.removeAll()
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
      let windowFrame = AXBannerFinder.frame(of: window)
    else {
      restoreIfNeeded(window: window, id: id)
      return
    }

    let resolved = resolvePositionAndAnimation(
      banner: banner, rules: rules, defaultPosition: defaultPosition)

    guard
      let calc = makeCalculator(
        id: id, windowFrame: windowFrame, bannerFrame: bannerFrame, screens: screens)
    else { return }

    guard calc.invariantHolds, let snapshot = windowSnapshots[id] else {
      logger.error(
        "BannerMover: invariant violated or window snapshot missing; skipping move"
      )
      return
    }
    let target = calc.targetOrigin(for: resolved.position)
    dispatchAnimation(
      resolved.animation, windowID: id, window: window, snapshot: snapshot, target: target)

    logger.debug(
      "BannerMover: window=\(String(format: "%016llx", id)) "
        + "rule=\(resolved.ruleName) "
        + "position=\(resolved.position.rawValue) "
        + "animation=\(resolved.animation.rawValue) "
        + "target=\(target)"
    )
  }

  /// Construct a `PositionCalculator` for this banner.
  ///
  /// Picks the target display, captures or fetches the per-window
  /// baseline, and resolves the primary-screen y-flip pivot. Returns
  /// nil (with a logged error) when any of those steps cannot complete.
  private func makeCalculator(
    id: UInt64, windowFrame: CGRect, bannerFrame: CGRect, screens: [ScreenInfo]
  ) -> PositionCalculator? {
    let centerAX = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
    let activeFallback = NSScreen.main.map(snapshot)
    let selector = DisplaySelector(screens: screens)
    guard
      let screen = selector.screenContaining(
        axPoint: centerAX, activeScreenFallback: activeFallback)
    else {
      logger.error("BannerMover: no screen available, skipping move")
      return nil
    }
    if windowSnapshots[id] == nil {
      windowSnapshots[id] = BannerWindowSnapshot(
        originalOrigin: windowFrame.origin,
        windowFrame: windowFrame,
        bannerFrame: bannerFrame
      )
    }
    guard let snapshot = windowSnapshots[id] else { return nil }
    // Resolve the primary display by its isPrimary flag so this matches
    // DisplaySelector.primary. `screens.first` would agree today by
    // coincidence (currentScreens() assigns isPrimary == idx == 0) but
    // would diverge if the array ordering ever drifted from the flag.
    guard let primaryHeight = screens.first(where: { $0.isPrimary })?.frame.height else {
      logger.error("BannerMover: no primary screen in list, skipping move")
      return nil
    }
    return PositionCalculator(
      windowFrame: snapshot.windowFrame,
      bannerFrame: snapshot.bannerFrame,
      screen: screen,
      primaryHeight: primaryHeight
    )
  }

  private struct ResolvedMatch {
    let position: Position
    let animation: Animation
    let ruleName: String
  }

  /// Extract banner text, resolve the source bundle ID, and find the
  /// first matching rule (if any).
  ///
  /// Returns the position and animation the matched rule overrides to,
  /// falling back to `defaultPosition` and `.none` when no rule matches,
  /// plus a human-readable rule name for diagnostic logging.
  private func resolvePositionAndAnimation(
    banner: AXUIElement, rules: [Rule], defaultPosition: Position
  ) -> ResolvedMatch {
    var bannerText = BannerTextExtractor.extract(from: banner)
    if let bid = AppResolver.bundleID(forAppName: bannerText.appName) {
      bannerText = BannerText(
        appName: bannerText.appName,
        bundleID: bid,
        title: bannerText.title,
        subtitle: bannerText.subtitle,
        body: bannerText.body
      )
    }
    let match = matcher.match(rules: rules, banner: bannerText)
    return ResolvedMatch(
      position: match?.rule.position ?? defaultPosition,
      animation: match?.rule.animation ?? .none,
      ruleName: match?.rule.name ?? "(default)"
    )
  }

  /// Dispatch per animation style.
  ///
  /// For shake/bounce the banner snaps to the target *immediately* (so
  /// the OS-default location is never briefly visible), and only the
  /// oscillation waits 150 ms for the OS's own banner-entry animation
  /// to finish. Slide is the exception: its first frame is the
  /// OS-original position, so it must wait the 150 ms before any frame
  /// fires.
  private func dispatchAnimation(
    _ animation: Animation,
    windowID: UInt64,
    window: AXUIElement,
    snapshot: BannerWindowSnapshot,
    target: CGPoint
  ) {
    switch animation {
    case .none:
      let frames = AnimationFrames.frames(style: .none, from: target, to: target)
      animator.animate(windowID: windowID, window: window, frames: frames, delay: 0)

    case .slide:
      let frames = AnimationFrames.frames(
        style: .slide, from: snapshot.originalOrigin, to: target)
      animator.animate(
        windowID: windowID, window: window, frames: frames, delay: Animator.startDelay)

    case .shake, .bounce:
      Animator.set(point: target, on: window)
      let frames = AnimationFrames.frames(style: animation, from: target, to: target)
      animator.animate(
        windowID: windowID, window: window, frames: frames, delay: Animator.startDelay)
    }
  }

  private func restoreIfNeeded(window: AXUIElement, id: UInt64) {
    guard let snapshot = windowSnapshots[id] else { return }
    animator.cancel(windowID: id)
    Animator.set(point: snapshot.originalOrigin, on: window)
    windowSnapshots.removeValue(forKey: id)
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
