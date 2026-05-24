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
/// rules (or the default), or forgets the window's tracked state when
/// there is no banner to move (e.g. the window is the expanded
/// Notification Center panel, or the banner has gone away).
///
/// `windowSnapshots` records each moved window's original geometry, keyed
/// by AX element identity (`elementID`). The snapshot is captured on the
/// first move and reused on later passes as the *stable baseline*, so the
/// target is computed from the banner's resting geometry and never drifts
/// as repeated passes observe the already-moved frame; it also supplies
/// the slide animation's start origin. The notification UI hands out a
/// fresh, short-lived window per banner — the OS resets it to the origin
/// for the next banner and destroys the old one — so the mover never
/// moves a window back; on dismiss it just drops the snapshot (keeping the
/// map bounded against the unique-per-banner ids). `reset()` clears
/// everything when the notification UI process exits and every tracked
/// element becomes invalid. The mover holds no AX observer itself; it is
/// handed the current window list each pass.
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
  ///
  /// Each window is repositioned to its resolved target the moment a banner
  /// is detected — the move anchors to the banner's known resting offset, so
  /// it does not wait for the slide-in animation to finish and never needs a
  /// follow-up pass.
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

  /// Move-or-restore one window.
  private func processWindow(
    _ window: AXUIElement,
    defaultPosition: Position,
    rules: [Rule],
    screens: [ScreenInfo]
  ) {
    let id = elementID(window)

    // Open Notification Center panel: never move it; drop any tracked state.
    if NotificationCenterPanelDetector.isPanel(window) {
      forget(id: id)
      return
    }

    // No banner inside this window (e.g. it was just dismissed): drop the
    // tracked state without moving the window. The window is a throwaway the
    // OS is about to destroy; moving it back would only snap the
    // still-sliding-out banner into view for a frame.
    guard let banner = AXBannerFinder.find(in: window),
      let liveBannerFrame = AXBannerFinder.frame(of: banner),
      let windowFrame = AXBannerFinder.frame(of: window)
    else {
      forget(id: id)
      return
    }

    // Anchor to the banner's *resting* spot, not its live frame. As a banner
    // slides in, its measured minX is still off the right edge, but it always
    // comes to rest the same inset from the container's right edge. Deriving
    // the resting frame lets us move the container the moment the banner
    // appears, so it slides into the target rather than appearing top-right
    // and then jumping. minY and size are stable during the horizontal slide.
    let bannerFrame = CGRect(
      x: windowFrame.width - liveBannerFrame.width - Constants.bannerRightPadding,
      y: liveBannerFrame.minY,
      width: liveBannerFrame.width,
      height: liveBannerFrame.height
    )

    let resolved = resolvePositionAndAnimation(
      banner: banner, rules: rules, defaultPosition: defaultPosition)

    guard
      let calc = makeCalculator(
        id: id, windowFrame: windowFrame, bannerFrame: bannerFrame, screens: screens)
    else { return }

    // The resting frame is always inside the window, so this guards only the
    // structural full-display-container invariant (broken by a macOS layout
    // change). Nothing needs to "settle": because we move the container and
    // the banner rides along to its known resting offset, the move can fire
    // on first detection.
    guard calc.invariantHolds else {
      logger.error(
        "BannerMover: full-display container invariant broken; skipping move. "
          + "windowFrame=\(windowFrame) bannerFrame=\(bannerFrame) "
          + "screenFrame=\(calc.screen.frame)"
      )
      return
    }
    if windowSnapshots[id] == nil {
      windowSnapshots[id] = BannerWindowSnapshot(
        originalOrigin: windowFrame.origin,
        windowFrame: windowFrame,
        bannerFrame: bannerFrame
      )
    }
    guard let snapshot = windowSnapshots[id] else { return }
    let target = calc.targetOrigin(for: resolved.position)
    dispatchAnimation(
      resolved.animation, windowID: id, window: window, snapshot: snapshot, target: target)

    logger.debug(
      "BannerMover: window=\(String(format: "%016llx", id)) "
        + "rule=\(resolved.ruleName) "
        + "position=\(resolved.position.rawValue) "
        + "animation=\(resolved.animation.rawValue) "
        + "bannerFrame=\(bannerFrame) "
        + "windowFrame=\(windowFrame) "
        + "target=\(target)"
    )
  }

  /// Construct a `PositionCalculator` for this banner.
  ///
  /// Picks the target display and resolves the primary-screen y-flip
  /// pivot, then builds the calculator from the stable per-window baseline
  /// when one exists, or from the live frame as a candidate the caller
  /// validates before adopting. Does not mutate the snapshot map. Returns
  /// nil (with a logged error) when the display or primary height cannot
  /// be resolved.
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
    // Resolve the primary display by its isPrimary flag so this matches
    // DisplaySelector.primary. `screens.first` would agree today by
    // coincidence (currentScreens() assigns isPrimary == idx == 0) but
    // would diverge if the array ordering ever drifted from the flag.
    guard let primaryHeight = screens.first(where: { $0.isPrimary })?.frame.height else {
      logger.error("BannerMover: no primary screen in list, skipping move")
      return nil
    }
    // Build from the stable baseline if one exists; otherwise from the live
    // frame as a candidate. The caller validates the invariant and adopts the
    // candidate as the baseline before using it.
    let baseline = windowSnapshots[id]
    return PositionCalculator(
      windowFrame: baseline?.windowFrame ?? windowFrame,
      bannerFrame: baseline?.bannerFrame ?? bannerFrame,
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

  /// Drop the tracked state for a window without moving it.
  ///
  /// Called when a window holds no banner to position (it was dismissed, or
  /// it is the Notification Center panel). The window is deliberately left
  /// where it is: the notification UI destroys it once its banner is gone,
  /// and moving it back would snap a still-sliding-out banner into view for
  /// a frame. Dropping the snapshot keeps the map bounded — the OS hands out
  /// a unique window id per banner — and cancelling any in-flight animation
  /// stops stray frames writing to a window that is going away. A no-op if
  /// the window was never moved (no snapshot to drop).
  private func forget(id: UInt64) {
    guard windowSnapshots.removeValue(forKey: id) != nil else { return }
    animator.cancel(windowID: id)
    logger.debug("BannerMover: released window \(String(format: "%016llx", id))")
  }

  /// Stable identity for an AX element across the fresh `AXUIElement`
  /// instances that `kAXWindows` returns on each pass.
  ///
  /// `kAXWindowsAttribute` hands back a new `AXUIElement` box on every
  /// query, so the raw pointer differs pass-to-pass even for the same
  /// window — which would make the per-window baseline and `Animator`
  /// state miss every time and produce a reposition flicker. `CFHash` is
  /// derived from the underlying element identity (consistent with
  /// `CFEqual`) and stays stable across those copies.
  private func elementID(_ el: AXUIElement) -> UInt64 {
    UInt64(CFHash(el))
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
