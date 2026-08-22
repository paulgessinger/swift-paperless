//
//  SyncPlanTests.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct SyncPlanTests {
  // Stable, ordered UUIDs so `sorted(by: uuidString)` is predictable in asserts.
  private static let a = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
  private static let b = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
  private static let c = UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!

  private func snapshot(
    _ id: UUID, hasToken: Bool = true, isEntireLibrary: Bool = false,
    syncOverCellular: Bool = false
  ) -> SyncPlan.ServerSnapshot {
    .init(
      id: id, hasToken: hasToken, isEntireLibrary: isEntireLibrary,
      syncOverCellular: syncOverCellular)
  }

  private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
  private let throttle: TimeInterval = 900

  @Test("The active server is never in the inactive action list")
  func activeExcluded() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a), snapshot(Self.b)],
      activeID: Self.a, lastSweep: [:], now: now, throttle: throttle,
      isExpensive: false, isConstrained: false)
    #expect(actions.map(\.serverID) == [Self.b])
  }

  @Test("Inactive servers are ordered deterministically by id")
  func stableOrdering() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.c), snapshot(Self.a), snapshot(Self.b)],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      isExpensive: false, isConstrained: false)
    #expect(actions.map(\.serverID) == [Self.a, Self.b, Self.c])
  }

  @Test("A recently-swept credentialed server is skipped")
  func throttledSkipped() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a), snapshot(Self.b)],
      activeID: nil,
      lastSweep: [Self.a: now.addingTimeInterval(-(throttle - 1))],
      now: now, throttle: throttle, isExpensive: false, isConstrained: false)
    #expect(actions.map(\.serverID) == [Self.b])
  }

  @Test("A stale (past-throttle) credentialed server is included")
  func staleIncluded() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a)],
      activeID: nil,
      lastSweep: [Self.a: now.addingTimeInterval(-(throttle + 1))],
      now: now, throttle: throttle, isExpensive: false, isConstrained: false)
    #expect(actions.map(\.serverID) == [Self.a])
  }

  @Test("An uncredentialed server yields a needsAuthOnly action, throttle-exempt")
  func uncredentialedNeedsAuthOnly() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a, hasToken: false)],
      activeID: nil,
      // Even "recently swept" it must re-emit so a freshly-arrived token is caught.
      lastSweep: [Self.a: now],
      now: now, throttle: throttle, isExpensive: false, isConstrained: false)
    #expect(
      actions == [SyncServerAction(serverID: Self.a, needsAuthOnly: true, runHeavyFill: false)])
  }

  @Test("Heavy fill requires both an allowed link and entireLibrary")
  func heavyFillGating() {
    func heavy(isExpensive: Bool, entire: Bool) -> Bool {
      SyncPlan.inactiveActions(
        connections: [snapshot(Self.a, isEntireLibrary: entire)],
        activeID: nil, lastSweep: [:], now: now, throttle: throttle,
        isExpensive: isExpensive, isConstrained: false
      ).first!.runHeavyFill
    }
    #expect(heavy(isExpensive: false, entire: true))
    #expect(!heavy(isExpensive: false, entire: false))
    #expect(!heavy(isExpensive: true, entire: true))
    #expect(!heavy(isExpensive: true, entire: false))
  }

  @Test(
    "A server's own syncOverCellular opts it into the heavy fill on an expensive link; a sibling without the opt-in stays cheap-only in the same sweep"
  )
  func perServerCellularOptIn() {
    let actions = SyncPlan.inactiveActions(
      connections: [
        snapshot(Self.a, isEntireLibrary: true, syncOverCellular: true),
        snapshot(Self.b, isEntireLibrary: true, syncOverCellular: false),
      ],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      isExpensive: true, isConstrained: false)
    #expect(actions.first(where: { $0.serverID == Self.a })?.runHeavyFill == true)
    #expect(actions.first(where: { $0.serverID == Self.b })?.runHeavyFill == false)
  }

  @Test("Low Data Mode blocks the heavy fill even for a server opted into cellular")
  func lowDataModeOverridesOptIn() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a, isEntireLibrary: true, syncOverCellular: true)],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      isExpensive: true, isConstrained: true)
    #expect(actions.first?.runHeavyFill == false)
  }

  @Test("Metered entireLibrary still runs the cheap tier (action present, heavy off)")
  func meteredStillSweepsCheap() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a, isEntireLibrary: true)],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      isExpensive: true, isConstrained: false)
    #expect(actions.count == 1)
    #expect(actions.first?.needsAuthOnly == false)
    #expect(actions.first?.runHeavyFill == false)
  }

  @Test("newlyAdded returns only genuinely new, non-active ids")
  func newlyAddedDiff() {
    let added = SyncPlan.newlyAdded(
      current: [Self.a, Self.b, Self.c], known: [Self.a], activeID: Self.b)
    #expect(added == [Self.c])
  }

  @Test("A newly-added server that is the active one is not swept by the engine")
  func newlyAddedExcludesActive() {
    let added = SyncPlan.newlyAdded(current: [Self.a], known: [], activeID: Self.a)
    #expect(added.isEmpty)
  }
}
