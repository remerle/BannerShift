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
/// attributes synchronously. For each window the mover either snaps the
/// contained banner to the global default position immediately, or
/// forgets the window's tracked state when there is no banner to move
/// (e.g. the window is the expanded Notification Center panel, or the
/// banner has gone away).
///
/// The pass is split into two phases for latency: the synchronous phase
/// covers everything required for the move to land (find banner,
/// compute target from the default position, write the AX position
/// attribute); the asynchronous phase does the rule resolution that
/// drives animation and pinning. Position is intentionally *not* a rule
/// concern any more — every banner moves to the default — because the
/// move is what the user notices visually, and gating it on
/// cross-process AX text extraction and pattern matching let the OS
/// paint the banner at the top-right default before our move landed.
/// Animation and pinning still vary per rule but kick in only after the
/// move is in flight.
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
/// the Notification Center panel. The snapshot's `animation` and
/// `ruleName` are written by the post-move async resolve; a later pass
/// that finds them already non-nil knows resolution has run and skips
/// scheduling it again. The notification UI hands out a fresh, short-lived
/// window per banner — the OS resets it to the origin for the next banner
/// and destroys the old one — so the mover never moves a window back; on
/// dismiss it just drops the snapshot (keeping the map bounded against the
/// unique-per-banner ids). `reset()` clears everything when the
/// notification UI process exits and every tracked element becomes
/// invalid. The mover holds no AX observer itself; it is handed the
/// current window list each pass.
final class BannerMover {
  private var windowSnapshots: [UInt64: BannerWindowSnapshot] = [:]
  private let logger: FileLogger
  private let preferences: Preferences
  private let ruleStore: RuleStore
  private let matcher: RuleMatcher
  private let animator: Animator
  /// Sink invoked exactly once per banner when the post-move async resolve
  /// finds a matched rule with `pinsToList` set.
  ///
  /// Fired on the main thread, like every other method here, on the
  /// run-loop turn after the move dispatches. Defaults to a no-op so
  /// non-pinning callers need not supply it.
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
    self.matcher = matcher
    self.ruleStore = ruleStore
    self.animator = animator
    self.onPin = onPin
  }

  /// Top-level pass: visit each notification UI window and move-or-restore.
  ///
  /// Each window is snapped to the global default the moment a banner is
  /// detected — geometry only, no rule resolution. The matched rule's
  /// animation and pin behavior, if any, fire on the next run-loop turn
  /// from `resolveAndFollowUp` so the cross-process AX text extraction
  /// they require stays off the move's critical path.
  func process(notificationUIWindows windows: [AXUIElement]) {
    let defaultPosition = preferences.position
    let screens = currentScreens()
    for window in windows {
      processWindow(
        window,
        defaultPosition: defaultPosition,
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
    // change). Bailing here also skips the async resolve (and so any
    // pinning): with no reliable geometry we are not repositioning the
    // banner, so we do not capture it either.
    guard calc.invariantHolds else {
      logger.error(
        "BannerMover: full-display container invariant broken; skipping move. "
          + "windowFrame=\(windowFrame) bannerFrame=\(bannerFrame) "
          + "screenFrame=\(calc.screen.frame)"
      )
      return
    }

    // Snapshot first sight (default position only, no rule resolution) and
    // snap to the target. Everything past this point is the synchronous
    // critical path; rule resolution, animation dispatch, and pin firing are
    // deferred to `resolveAndFollowUp` so this method returns the moment the
    // AX position write has been submitted.
    let firstSight = recordFirstSight(
      id: id, frames: (windowFrame, bannerFrame), defaultPosition: defaultPosition)
    let target = calc.targetOrigin(for: firstSight.snapshot.position)
    Animator.set(point: target, on: window)

    logger.debug(
      "BannerMover move: window=\(String(format: "%016llx", id)) "
        + "detection=\(detection) "
        + "position=\(firstSight.snapshot.position.rawValue) "
        + "bannerFrame=\(bannerFrame) "
        + "windowFrame=\(windowFrame) "
        + "target=\(target)"
    )

    if firstSight.isFirstSight {
      // Defer rule resolution (banner text extraction, rule match, animation
      // dispatch, pin firing) to the next main run-loop turn. By then the AX
      // set above has been picked up by NotificationCenter and the banner is
      // settling at the target, so the expensive cross-process AX text reads
      // and any panel-render work the pin triggers happen entirely off the
      // move's critical path.
      DispatchQueue.main.async { [weak self] in
        self?.resolveAndFollowUp(id: id, banner: banner, window: window, target: target)
      }
    }
  }

  /// Result of `recordFirstSight`: the cached or freshly-created snapshot
  /// plus a flag indicating whether this was the first time we saw the
  /// window (and so whether the caller should schedule the async resolve).
  private struct FirstSightResult {
    let snapshot: BannerWindowSnapshot
    let isFirstSight: Bool
  }

  /// Record a first-sighting snapshot or return the cached one.
  ///
  /// The snapshot stores the geometry needed for repositioning and the
  /// default position the banner was moved to. `animation` and `ruleName`
  /// are deliberately left nil here; the post-move async resolve writes
  /// them when it completes. A later pass that finds the snapshot still
  /// in the map returns `isFirstSight = false` so the caller does not
  /// re-schedule the resolve.
  private func recordFirstSight(
    id: UInt64,
    frames: (window: CGRect, banner: CGRect),
    defaultPosition: Position
  ) -> FirstSightResult {
    if let existing = windowSnapshots[id] {
      return FirstSightResult(snapshot: existing, isFirstSight: false)
    }
    let snapshot = BannerWindowSnapshot(
      originalOrigin: frames.window.origin,
      windowFrame: frames.window,
      bannerFrame: frames.banner,
      position: defaultPosition
    )
    windowSnapshots[id] = snapshot
    return FirstSightResult(snapshot: snapshot, isFirstSight: true)
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

  /// Result of resolving a banner's matched rule.
  private struct ResolvedMatch {
    let animation: Animation
    let ruleName: String
    /// Non-nil when the matched rule pins; carries the captured fields to
    /// hand to `onPin`.
    let pinned: CapturedNotification?
  }

  /// Post-move async work: extract banner text, match a rule, update the
  /// snapshot, dispatch any rule-requested animation, and fire `onPin` if
  /// the matched rule pins.
  ///
  /// Runs on the next main run-loop turn after the synchronous move
  /// dispatches. If the snapshot has been evicted in the meantime (banner
  /// dismissed, or the window turned out to be the Notification Center
  /// panel and was restored) the resolve bails — there is nothing left to
  /// follow up on. The banner AX element passed in may be stale by the
  /// time this runs; AX attribute reads on a destroyed element return
  /// empty/`.invalidUIElement`, the text extraction yields an empty
  /// `BannerText`, the matcher finds no match, and the resolve quietly
  /// records `(default)` and does not pin.
  private func resolveAndFollowUp(
    id: UInt64,
    banner: AXUIElement,
    window: AXUIElement,
    target: CGPoint
  ) {
    guard windowSnapshots[id] != nil else { return }
    let rules = ruleStore.load()
    let resolved = resolveAnimationAndPin(banner: banner, rules: rules)

    // Write the resolution back into the snapshot so a later pass knows the
    // resolve has run (and so subsequent debounced passes do not schedule
    // another one).
    if var snapshot = windowSnapshots[id] {
      snapshot.animation = resolved.animation
      snapshot.ruleName = resolved.ruleName
      windowSnapshots[id] = snapshot
    }

    dispatchAnimation(resolved.animation, windowID: id, window: window, target: target)

    if let pinned = resolved.pinned {
      onPin(pinned)
    }

    logger.debug(
      "BannerMover resolve: window=\(String(format: "%016llx", id)) "
        + "rule=\(resolved.ruleName) "
        + "animation=\(resolved.animation.rawValue) "
        + "pinned=\(resolved.pinned != nil)"
    )
  }

  /// Extract banner text, resolve the source bundle ID, find the first
  /// matching rule (if any), and translate the result into the animation
  /// to dispatch and any captured notification to pin.
  ///
  /// `.none` and `(default)` are the no-match fallbacks. The no-rule
  /// fast path additionally skips the AX subtree text extraction
  /// entirely; with no rules to match, the banner's text is irrelevant.
  private func resolveAnimationAndPin(
    banner: AXUIElement, rules: [Rule]
  ) -> ResolvedMatch {
    guard !rules.isEmpty else {
      return ResolvedMatch(animation: .none, ruleName: "(default)", pinned: nil)
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
      animation: match?.rule.animation ?? .none,
      ruleName: match?.rule.name ?? "(default)",
      pinned: pinned)
  }

  /// Dispatch any oscillation the matched rule requested.
  ///
  /// The banner is already at `target` from the synchronous move that ran
  /// one main run-loop turn earlier; this method only schedules the
  /// oscillation. `.none` is a no-op: the move already happened. For
  /// shake/bounce the oscillation waits 150 ms for the OS's own
  /// banner-entry animation to finish, then begins from the banner's
  /// settled position.
  private func dispatchAnimation(
    _ animation: Animation,
    windowID: UInt64,
    window: AXUIElement,
    target: CGPoint
  ) {
    switch animation {
    case .none:
      // The synchronous move in processWindow already placed the banner at
      // `target`; nothing further to do here. Cancel any in-flight animation
      // from an earlier (now superseded) pass so it cannot keep writing
      // frames onto this window.
      animator.cancel(windowID: windowID)

    case .shake, .bounce:
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
