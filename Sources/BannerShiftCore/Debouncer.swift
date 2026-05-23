import Foundation

/// Trailing-edge debouncer: calls to `schedule` cancel any previously
/// pending action, and the most recent action fires once after
/// `interval` of quiet time.
///
/// Used to coalesce bursts of AX notifications under heavy load (e.g.
/// when ten banners arrive in the same tick) so the reposition pass
/// runs at most once per `Constants.eventDebounceInterval` window.
/// Thread-safe so the AX callback (main thread) and the
/// `applicationWillTerminate` cleanup can both touch it.
public final class Debouncer {
  private let interval: TimeInterval
  private let queue: DispatchQueue
  private var workItem: DispatchWorkItem?
  private let lock = NSLock()

  /// - Parameters:
  ///   - interval: Quiet time required before the scheduled action
  ///     fires. A new `schedule` call resets the clock.
  ///   - queue: Dispatch queue the action runs on. Defaults to `.main`
  ///     because the reposition pipeline touches AX and AppKit.
  public init(interval: TimeInterval, queue: DispatchQueue = .main) {
    self.interval = interval
    self.queue = queue
  }

  /// Replace any pending action with `action` and arm a fresh timer.
  ///
  /// The previous pending action, if any, is cancelled rather than run.
  /// This is intentional: only the *latest* schedule should fire,
  /// because a follow-up event will have already observed the AX state
  /// the earlier event was reacting to.
  public func schedule(_ action: @escaping () -> Void) {
    lock.lock()
    workItem?.cancel()
    let item = DispatchWorkItem(block: action)
    workItem = item
    lock.unlock()
    queue.asyncAfter(deadline: .now() + interval, execute: item)
  }

  /// Cancel any pending action without firing it.
  ///
  /// Called when the notification UI process terminates: any pending
  /// work would be operating on now-invalid AX elements.
  public func cancel() {
    lock.lock()
    workItem?.cancel()
    workItem = nil
    lock.unlock()
  }
}
