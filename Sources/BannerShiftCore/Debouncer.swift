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
