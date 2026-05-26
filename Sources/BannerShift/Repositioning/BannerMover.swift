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
/// On macOS 26 the banner element's AX subrole is assigned *after* the
/// banner is already on screen, so keying off the subrole alone misses
/// fast-arriving banners (the per-banner window can be replaced before the
/// subrole lands). The mover therefore finds the banner two ways — by
/// subrole, or, failing that, structurally via
/// `AXBannerFinder.findBannerByStructure` — and in both cases measures the
/// element's real frame. There is no assumed banner geometry: a banner's
/// height varies with its content, so the resting frame is always read from
/// the live element, never synthesised.
///
/// `windowSnapshots` records each moved window's original geometry, keyed
/// by AX element identity (`elementID`). The snapshot is captured on the
/// first move and reused on later passes as the *stable baseline*, so the
/// target is computed from the banner's resting geometry and never drifts
/// as repeated passes observe the already-moved frame; its `originalOrigin`
/// also lets `restoreMisMovedPanel` put back a window that turned out to be
/// the Notification Center panel. The notification UI hands out a
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
  /// Sink invoked exactly once per banner (at first-sight) when a matched rule has `pinsToList` set.
  ///
  /// Fired on the main thread, like every other method here. Defaults to a
  /// no-op so non-pinning callers need not supply it.
  private let onPin: (CapturedNotification) -> Void

  init(
    logger: FileLogger,
    preferences: Preferences,
    ruleStore: RuleStore,
    matcher: RuleMatcher,
    animator: Animator,
    onPin: @escaping (CapturedNotification) -> Void = { _ in }
  ) {
    self.logger = logger
    self.preferences = preferences
    self.ruleStore = ruleStore
    self.matcher = matcher
    self.animator = animator
    self.onPin = onPin
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

    // Open Notification Center panel: never move it. If we moved it before its
    // panel marker was populated (the marker can lag, like the banner subrole),
    // put it back so the panel isn't left displaced.
    if NotificationCenterPanelDetector.isPanel(window) {
      restoreMisMovedPanel(window: window, id: id)
      return
    }

    guard let windowFrame = AXBannerFinder.frame(of: window) else {
      forget(id: id)
      return
    }

    // macOS assigns the banner element's AX subrole *after* it is already on
    // screen, so the subrole-based finder misses a banner that is visibly
    // rendering — most visibly under a fast burst, where the window can be
    // replaced before the subrole ever lands. Fall back to the structural
    // finder, which locates the same element by its place in the notification
    // stack and reads its real frame. A window with neither is a dismissed
    // banner's throwaway window (about to be destroyed) or an unrelated helper
    // window: drop tracked state without moving — see `forget`.
    let subroleBanner = AXBannerFinder.find(in: window)
    guard
      let banner = subroleBanner ?? AXBannerFinder.findBannerByStructure(in: window),
      let liveBannerFrame = AXBannerFinder.frame(of: banner)
    else {
      forget(id: id)
      return
    }
    // Which finder matched, for diagnostics: "structure" means the subrole had
    // not landed yet and we caught the banner by tree structure instead.
    let detection = subroleBanner != nil ? "subrole" : "structure"

    // Anchor to the banner's *resting* spot — not the live minX, which is still
    // off the right edge mid-slide-in — so the move can fire on first sight:
    // the banner always comes to rest the same inset from the container's right
    // edge, and its size/minY are stable during the horizontal slide. The
    // conversion to window-relative coordinates (including the y-rebase that
    // makes secondary displays work) lives in Core and is unit-tested.
    let bannerFrame = PositionCalculator.restingBannerFrame(
      windowFrame: windowFrame, liveBannerFrame: liveBannerFrame)

    guard
      let calc = makeCalculator(
        id: id, windowFrame: windowFrame, bannerFrame: bannerFrame, screens: screens)
    else { return }

    // The resting frame is always inside the window, so this guards only the
    // structural full-display-container invariant (broken by a macOS layout
    // change). Nothing needs to "settle": because we move the container and
    // the banner rides along to its known resting offset, the move can fire
    // on first detection. Bailing here also skips pinning (the first-sight
    // block below is what fires `onPin`): with no reliable geometry we are not
    // repositioning the banner, so we do not capture it either. Resolving the
    // rule match only *after* this guard also keeps the expensive AX text
    // extraction off the path when the invariant is broken.
    guard calc.invariantHolds else {
      logger.error(
        "BannerMover: full-display container invariant broken; skipping move. "
          + "windowFrame=\(windowFrame) bannerFrame=\(bannerFrame) "
          + "screenFrame=\(calc.screen.frame)"
      )
      return
    }

    // Resolve placement once per banner (cached in the snapshot), then move.
    let placement = placement(
      id: id, banner: banner, frames: (windowFrame, bannerFrame),
      rules: rules, defaultPosition: defaultPosition)

    let target = calc.targetOrigin(for: placement.position)
    dispatchAnimation(placement.animation, windowID: id, window: window, target: target)

    logger.debug(
      "BannerMover: window=\(String(format: "%016llx", id)) "
        + "detection=\(detection) "
        + "rule=\(placement.ruleName) "
        + "position=\(placement.position.rawValue) "
        + "animation=\(placement.animation.rawValue) "
        + "bannerFrame=\(bannerFrame) "
        + "windowFrame=\(windowFrame) "
        + "target=\(target)"
    )
  }

  /// The cached placement for a window, resolving it on first sight.
  ///
  /// A window identity maps to exactly one banner whose text never changes, so
  /// the rule match (and its several cross-process AX text reads) runs once per
  /// banner: the first sighting resolves the placement, records the resting
  /// baseline used by later passes' geometry, and fires `onPin` once if the
  /// matched rule pins. Later debounced passes find the cached snapshot and
  /// reuse it, so the expensive extraction never repeats and the pin is never
  /// double-counted. Caller must have already validated `invariantHolds`.
  private func placement(
    id: UInt64,
    banner: AXUIElement,
    frames: (window: CGRect, banner: CGRect),
    rules: [Rule],
    defaultPosition: Position
  ) -> BannerWindowSnapshot {
    if let existing = windowSnapshots[id] { return existing }
    let resolved = resolvePositionAndAnimation(
      banner: banner, rules: rules, defaultPosition: defaultPosition)
    let snapshot = BannerWindowSnapshot(
      originalOrigin: frames.window.origin,
      windowFrame: frames.window,
      bannerFrame: frames.banner,
      position: resolved.position,
      animation: resolved.animation,
      ruleName: resolved.ruleName
    )
    windowSnapshots[id] = snapshot
    if let pinned = resolved.pinned {
      onPin(pinned)
    }
    return snapshot
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
    /// Non-nil when the matched rule pins; carries the captured fields to
    /// hand to `onPin` at first-sight.
    let pinned: CapturedNotification?
  }

  /// Extract banner text, resolve the source bundle ID, and find the
  /// first matching rule (if any).
  ///
  /// Returns the position and animation the matched rule overrides to,
  /// falling back to `defaultPosition` and `.none` when no rule matches,
  /// plus a human-readable rule name for diagnostic logging. Also populates
  /// `pinned` with the captured banner text when the matched rule has
  /// `pinsToList` set, and nil otherwise (including the no-rule fast path).
  private func resolvePositionAndAnimation(
    banner: AXUIElement, rules: [Rule], defaultPosition: Position
  ) -> ResolvedMatch {
    // No rules: the default position applies and the banner's text is
    // irrelevant. Skip the AX subtree text extraction (several cross-process
    // AX calls) so it stays off the first-move critical path.
    guard !rules.isEmpty else {
      return ResolvedMatch(
        position: defaultPosition, animation: .none, ruleName: "(default)", pinned: nil)
    }
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
    let pinned: CapturedNotification? =
      (match?.rule.pinsToList == true)
      ? CapturedNotification(
        appName: bannerText.appName, bundleID: bannerText.bundleID,
        title: bannerText.title, body: bannerText.body)
      : nil
    return ResolvedMatch(
      position: match?.rule.position ?? defaultPosition,
      animation: match?.rule.animation ?? .none,
      ruleName: match?.rule.name ?? "(default)",
      pinned: pinned)
  }

  /// Dispatch per animation style.
  ///
  /// `.none` snaps to the target synchronously: there is no animation, so
  /// scheduling even a single zero-offset frame through the animator would
  /// only defer the move by an extra run-loop turn. For shake/bounce the
  /// banner likewise snaps to the target *immediately* (so the OS-default
  /// location is never briefly visible), and only the oscillation waits
  /// 150 ms for the OS's own banner-entry animation to finish.
  private func dispatchAnimation(
    _ animation: Animation,
    windowID: UInt64,
    window: AXUIElement,
    target: CGPoint
  ) {
    switch animation {
    case .none:
      // Cancel any in-flight animation for this window (a superseded
      // shake/bounce) so it can't keep writing frames, then move now. This
      // is what `animator.animate` would do internally, minus the extra
      // asyncAfter hop that a zero-offset frame schedule incurs.
      animator.cancel(windowID: windowID)
      Animator.set(point: target, on: window)

    case .shake, .bounce:
      Animator.set(point: target, on: window)
      let frames = AnimationFrames.frames(style: animation, to: target)
      animator.animate(
        windowID: windowID, window: window, frames: frames, delay: Animator.startDelay)
    }
  }

  /// Restore a panel we moved before recognizing it as the panel, then forget.
  ///
  /// The container-detection path can move a window on the first pass before
  /// its panel marker is populated. Once `isPanel` reports true, put the
  /// window back at its captured origin so the open panel isn't left
  /// displaced. A no-op (beyond forgetting) if we never moved it.
  private func restoreMisMovedPanel(window: AXUIElement, id: UInt64) {
    guard let snapshot = windowSnapshots.removeValue(forKey: id) else { return }
    animator.cancel(windowID: id)
    Animator.set(point: snapshot.originalOrigin, on: window)
    logger.debug("BannerMover: restored mis-moved panel \(String(format: "%016llx", id))")
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
