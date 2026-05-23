import AppKit
import ApplicationServices
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
      processWindow(
        window,
        defaultPosition: defaultPosition,
        rules: rules,
        screens: screens
      )
    }
  }

  /// Clear all per-window state and cancel in-flight animations.
  /// Called when the notification UI process (`NotificationCenter`) exits,
  /// because every AX element we were tracking is now invalid and any
  /// in-flight animation would be writing positions to dangling pointers.
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
      let windowFrame = AXBannerFinder.frame(of: window)
    else {
      restoreIfNeeded(window: window, id: id)
      return
    }

    // Extract banner text, resolve bundle ID, find matching rule.
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
    let position = match?.rule.position ?? defaultPosition
    let animation = match?.rule.animation ?? .none

    // Pick the display the window currently belongs to.
    let centerAX = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
    let activeFallback = NSScreen.main.map(snapshot)
    let selector = DisplaySelector(screens: screens)
    guard
      let screen = selector.screenContaining(
        axPoint: centerAX,
        activeScreenFallback: activeFallback
      )
    else {
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

    let primaryHeight = screens.first?.frame.height ?? screen.frame.height
    let calc = PositionCalculator(
      windowFrame: baseline.windowFrame,
      bannerFrame: baseline.bannerFrame,
      screen: screen,
      primaryHeight: primaryHeight
    )
    guard calc.invariantHolds else {
      logger.error(
        "BannerMover: window-height invariant violated "
          + "(window=\(baseline.windowFrame.height), "
          + "screen=\(screen.frame.height)); skipping move"
      )
      return
    }
    let target = calc.targetOrigin(for: position)

    // Dispatch per animation style. For shake/bounce the banner must snap
    // to the target *immediately* (so the OS-default location is never
    // briefly visible), and only the oscillation waits 150 ms for the OS's
    // own banner-entry animation to finish. Slide is the exception: its
    // first frame is the OS-original position, so it must wait the 150 ms
    // before any frame fires.
    switch animation {
    case .none:
      let frames = AnimationFrames.frames(style: .none, from: target, to: target)
      animator.animate(windowID: id, window: window, frames: frames, delay: 0)
    case .slide:
      let frames = AnimationFrames.frames(
        style: .slide, from: baseline.originalOrigin, to: target)
      animator.animate(windowID: id, window: window, frames: frames, delay: Animator.startDelay)
    case .shake, .bounce:
      Animator.set(point: target, on: window)
      let frames = AnimationFrames.frames(style: animation, from: target, to: target)
      animator.animate(windowID: id, window: window, frames: frames, delay: Animator.startDelay)
    }

    logger.debug(
      "BannerMover: window=\(String(format: "%016llx", id)) "
        + "rule=\(match?.rule.name ?? "(default)") "
        + "position=\(position.rawValue) animation=\(animation.rawValue) "
        + "target=\(target)"
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
