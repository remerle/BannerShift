import Foundation
import Testing

@testable import BannerShiftCore

@Test func firesOnLeadingEdgeForIsolatedEvent() async throws {
  let queue = DispatchQueue(label: "test")
  let debouncer = Debouncer(interval: 0.05, queue: queue)
  var fired = 0
  debouncer.schedule { fired += 1 }
  // 200 ms margin (4x interval) to absorb CI scheduling jitter; q.sync drains
  // the queue once we are past the window so the assertion is deterministic.
  try await Task.sleep(nanoseconds: 200_000_000)
  queue.sync {}  // drain pending work items
  // An isolated schedule fires once, on the leading edge: no follow-up
  // arrived during the window, so no trailing run is armed.
  #expect(fired == 1)
}

@Test func burstFiresLeadingPlusOneTrailing() async throws {
  let queue = DispatchQueue(label: "test")
  let debouncer = Debouncer(interval: 0.05, queue: queue)
  var fired = 0
  debouncer.schedule { fired += 1 }
  debouncer.schedule { fired += 1 }
  debouncer.schedule { fired += 1 }
  // 500 ms margin (10x interval); the burst path has more dispatch traffic, so
  // we give the queue extra headroom before draining and asserting.
  try await Task.sleep(nanoseconds: 500_000_000)
  queue.sync {}
  // First schedule fires immediately (leading); the next two are coalesced
  // into a single trailing run that fires when the window closes.
  #expect(fired == 2)
}

@Test func cancelPreventsLeadingFire() async throws {
  let queue = DispatchQueue(label: "test")
  let debouncer = Debouncer(interval: 0.05, queue: queue)
  var fired = 0
  debouncer.schedule { fired += 1 }
  debouncer.cancel()
  // 500 ms margin; we want to give the cancelled leading item every
  // opportunity to erroneously fire before asserting fired == 0. cancel()
  // must stop the queued leading run, not just pending trailing work.
  try await Task.sleep(nanoseconds: 500_000_000)
  queue.sync {}
  #expect(fired == 0)
}

@Test func cancelPreventsTrailingFire() async throws {
  let queue = DispatchQueue(label: "test")
  let debouncer = Debouncer(interval: 0.05, queue: queue)
  var fired = 0
  // Two rapid schedules: leading fires, trailing is armed. Cancel before the
  // window closes and neither the (already-run) leading nor the pending
  // trailing should leave anything queued to fire afterward.
  debouncer.schedule { fired += 1 }
  debouncer.schedule { fired += 1 }
  queue.sync {}  // let the leading run drain (fired == 1)
  debouncer.cancel()
  try await Task.sleep(nanoseconds: 500_000_000)
  queue.sync {}
  #expect(fired == 1)
}
