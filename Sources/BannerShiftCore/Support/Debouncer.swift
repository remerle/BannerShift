import Foundation

/// Leading-plus-trailing debouncer: the first `schedule` after an idle
/// period runs its action *immediately* and opens a coalescing window;
/// further calls inside that window are folded into a single trailing
/// run that fires once the window closes.
///
/// The leading edge is what keeps a freshly posted banner from being
/// visibly repositioned. A banner slides in over several AX
/// notifications; a pure trailing debounce waits for that storm to go
/// quiet before moving, by which point the banner has already animated
/// into the OS-default position and the move reads as a jump. Firing on
/// the first event repositions the container before the banner is
/// on-screen.
///
/// The trailing run is the smart half: it is armed only when a *later*
/// schedule arrives during the window — i.e. only when there is newer AX
/// state the leading run could not have seen (e.g. the leading run fired
/// while the window existed but its banner subtree was not yet attached).
/// An isolated event therefore runs the action exactly once. Under burst
/// the action runs at most about twice per `interval` (one leading, one
/// trailing) no matter how many notifications arrive, so the burst
/// protection the trailing debounce gave us still holds. Thread-safe so
/// the AX callback (main thread) and the `applicationWillTerminate`
/// cleanup can both touch it.
public final class Debouncer {
  private let interval: TimeInterval
  private let queue: DispatchQueue
  /// In-flight leading run, retained so `cancel()` can stop it before it
  /// reaches the queue; otherwise a teardown could let a leading run
  /// touch now-invalid AX elements.
  private var leadingItem: DispatchWorkItem?
  /// Pending coalesced trailing run, replaced by each follow-up schedule
  /// so only the latest AX state is re-applied when the window closes.
  private var trailingItem: DispatchWorkItem?
  /// End of the current coalescing window.
  ///
  /// While `now < cooldownUntil` the leading edge has already fired and
  /// further schedules feed the trailing run; nil (or elapsed) means
  /// idle, so the next schedule fires on the leading edge.
  private var cooldownUntil: DispatchTime?
  private let lock = NSLock()

  /// - Parameters:
  ///   - interval: Coalescing window. The first schedule after an idle
  ///     period fires immediately and opens a window of this length;
  ///     schedules within it are folded into one trailing run.
  ///   - queue: Dispatch queue the action runs on. Defaults to `.main`
  ///     because the reposition pipeline touches AX and AppKit.
  public init(interval: TimeInterval, queue: DispatchQueue = .main) {
    self.interval = interval
    self.queue = queue
  }

  /// Run `action` on the leading edge if idle, otherwise arm/replace the
  /// trailing run for the end of the current coalescing window.
  ///
  /// A follow-up schedule's action replaces any pending trailing work
  /// because the later call has observed AX state at least as current as
  /// the one it replaces.
  public func schedule(_ action: @escaping () -> Void) {
    lock.lock()
    let now = DispatchTime.now()
    let idle = cooldownUntil.map { now >= $0 } ?? true
    var leading: DispatchWorkItem?
    var trailing: (item: DispatchWorkItem, deadline: DispatchTime)?
    if idle {
      cooldownUntil = now + interval
      trailingItem?.cancel()
      trailingItem = nil
      let item = DispatchWorkItem(block: action)
      leadingItem = item
      leading = item
    } else if let deadline = cooldownUntil {
      trailingItem?.cancel()
      let item = DispatchWorkItem(block: action)
      trailingItem = item
      trailing = (item, deadline)
    }
    lock.unlock()

    // Dispatch outside the lock. A concurrent cancel() between unlock and
    // submit cancels the retained items first; DispatchWorkItem checks
    // isCancelled before executing, so a cancelled submit becomes a no-op.
    // Submitting inside the lock would deadlock when queue is a serial
    // queue executing on the locking thread (the production case: queue
    // == .main, caller on the main thread).
    if let leading {
      queue.async(execute: leading)
    }
    if let trailing {
      queue.asyncAfter(deadline: trailing.deadline, execute: trailing.item)
    }
  }

  /// Cancel any pending leading or trailing action and reset the window.
  ///
  /// Called when the notification UI process terminates: any pending
  /// work would be operating on now-invalid AX elements. Clearing the
  /// window means the next `schedule` fires on the leading edge again.
  public func cancel() {
    lock.lock()
    leadingItem?.cancel()
    leadingItem = nil
    trailingItem?.cancel()
    trailingItem = nil
    cooldownUntil = nil
    lock.unlock()
  }
}
