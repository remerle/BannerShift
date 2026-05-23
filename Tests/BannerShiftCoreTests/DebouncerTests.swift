import Foundation
import Testing

@testable import BannerShiftCore

@Test func firesAfterInterval() async throws {
  let q = DispatchQueue(label: "test")
  let debouncer = Debouncer(interval: 0.05, queue: q)
  var fired = 0
  debouncer.schedule { fired += 1 }
  // 200 ms margin (4x debounce) to absorb CI scheduling jitter; q.sync drains
  // the queue once we are past the deadline so the assertion is deterministic.
  try await Task.sleep(nanoseconds: 200_000_000)
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
  // 500 ms margin (10x debounce); replace path has more dispatch traffic, so
  // we give the queue extra headroom before draining and asserting.
  try await Task.sleep(nanoseconds: 500_000_000)
  q.sync {}
  #expect(fired == 1)
}

@Test func cancelPreventsFire() async throws {
  let q = DispatchQueue(label: "test")
  let debouncer = Debouncer(interval: 0.05, queue: q)
  var fired = 0
  debouncer.schedule { fired += 1 }
  debouncer.cancel()
  // 500 ms margin; we want to give the cancelled item every opportunity to
  // erroneously fire before asserting fired == 0.
  try await Task.sleep(nanoseconds: 500_000_000)
  q.sync {}
  #expect(fired == 0)
}
