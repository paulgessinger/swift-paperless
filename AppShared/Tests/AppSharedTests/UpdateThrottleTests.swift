import Foundation
import Testing

@testable import AppShared

@MainActor
@Suite
struct UpdateThrottleTests {
  @Test("The first update runs at once, and a burst after it runs only its last update, once")
  func coalescesABurst() async throws {
    let throttle = UpdateThrottle(interval: .milliseconds(100))
    var applied: [Int] = []

    throttle.run { applied.append(1) }
    #expect(applied == [1])
    for value in 2...5 {
      throttle.run { applied.append(value) }
    }
    #expect(applied == [1])

    try await waitUntil({ applied.count == 2 }, "the trailing update never ran")
    #expect(applied == [1, 5])
    try await Task.sleep(for: .milliseconds(150))
    #expect(applied == [1, 5])
  }

  @Test("An update after a quiet interval runs at once")
  func runsAtOnceAfterQuiet() async throws {
    let throttle = UpdateThrottle(interval: .milliseconds(20))
    var applied: [Int] = []

    throttle.run { applied.append(1) }
    try await Task.sleep(for: .milliseconds(40))
    throttle.run { applied.append(2) }
    #expect(applied == [1, 2])
  }

  @Test("A zero interval runs every update at once")
  func zeroIntervalRunsEveryUpdate() {
    let throttle = UpdateThrottle(interval: .zero)
    var applied: [Int] = []

    for value in 1...3 {
      throttle.run { applied.append(value) }
    }
    #expect(applied == [1, 2, 3])
  }

  @Test("A cancelled update never runs")
  func cancelDropsThePendingUpdate() async throws {
    let throttle = UpdateThrottle(interval: .milliseconds(50))
    var applied: [Int] = []

    throttle.run { applied.append(1) }
    throttle.run { applied.append(2) }
    throttle.cancel()
    try await Task.sleep(for: .milliseconds(100))
    #expect(applied == [1])

    throttle.run { applied.append(3) }
    #expect(applied == [1, 3])
  }
}
