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
      cost: .unrestricted)
    #expect(actions.map(\.serverID) == [Self.b])
  }

  @Test("Inactive servers are ordered deterministically by id")
  func stableOrdering() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.c), snapshot(Self.a), snapshot(Self.b)],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      cost: .unrestricted)
    #expect(actions.map(\.serverID) == [Self.a, Self.b, Self.c])
  }

  @Test("A recently-swept credentialed server is skipped")
  func throttledSkipped() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a), snapshot(Self.b)],
      activeID: nil,
      lastSweep: [Self.a: now.addingTimeInterval(-(throttle - 1))],
      now: now, throttle: throttle, cost: .unrestricted)
    #expect(actions.map(\.serverID) == [Self.b])
  }

  @Test("A stale (past-throttle) credentialed server is included")
  func staleIncluded() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a)],
      activeID: nil,
      lastSweep: [Self.a: now.addingTimeInterval(-(throttle + 1))],
      now: now, throttle: throttle, cost: .unrestricted)
    #expect(actions.map(\.serverID) == [Self.a])
  }

  @Test("An uncredentialed server yields a needsAuthOnly action, throttle-exempt")
  func uncredentialedNeedsAuthOnly() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a, hasToken: false)],
      activeID: nil,
      // Even "recently swept" it must re-emit so a freshly-arrived token is caught.
      lastSweep: [Self.a: now],
      now: now, throttle: throttle, cost: .unrestricted)
    #expect(
      actions == [SyncServerAction(serverID: Self.a, needsAuthOnly: true, phases: .nothing)])
  }

  @Test("Heavy fill requires both an allowed link and entireLibrary")
  func heavyFillGating() {
    func heavy(isExpensive: Bool, entire: Bool) -> Bool {
      SyncPlan.inactiveActions(
        connections: [snapshot(Self.a, isEntireLibrary: entire)],
        activeID: nil, lastSweep: [:], now: now, throttle: throttle,
        cost: LinkCost(isExpensive: isExpensive, isConstrained: false)
      ).first!.phases.contains(.fill)
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
      cost: LinkCost(isExpensive: true, isConstrained: false))
    #expect(actions.first(where: { $0.serverID == Self.a })?.phases.contains(.fill) == true)
    #expect(actions.first(where: { $0.serverID == Self.b })?.phases.contains(.fill) == false)
  }

  @Test("Low Data Mode blocks the heavy fill even for a server opted into cellular")
  func lowDataModeOverridesOptIn() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a, isEntireLibrary: true, syncOverCellular: true)],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      cost: LinkCost(isExpensive: true, isConstrained: true))
    #expect(actions.first?.phases.contains(.fill) == false)
  }

  @Test("Metered entireLibrary still runs the cheap tier (action present, heavy off)")
  func meteredStillSweepsCheap() {
    let actions = SyncPlan.inactiveActions(
      connections: [snapshot(Self.a, isEntireLibrary: true)],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      cost: LinkCost(isExpensive: true, isConstrained: false))
    #expect(actions.count == 1)
    #expect(actions.first?.needsAuthOnly == false)
    #expect(actions.first?.phases.contains(.fill) == false)
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

  // MARK: - The shared phase rule

  // `phases` is what both drivers ask: the sweep through `inactiveActions`, the
  // active server directly from the store's callers. These pin the rule itself,
  // so a change to it can't quietly apply to only one of them.

  @Test("Both gates must pass for the fill to be planned")
  func fillNeedsModeAndLink() {
    let unmetered = SyncCondition(
      cost: .unrestricted,
      syncOverCellular: false)
    let metered = SyncCondition(
      cost: LinkCost(isExpensive: true, isConstrained: false),
      syncOverCellular: false)

    #expect(SyncPlan.phases(isEntireLibrary: true, condition: unmetered) == .full)
    #expect(SyncPlan.phases(isEntireLibrary: true, condition: metered) == .cheap)
    #expect(SyncPlan.phases(isEntireLibrary: false, condition: unmetered) == .cheap)
    #expect(SyncPlan.phases(isEntireLibrary: false, condition: metered) == .cheap)
  }

  @Test("A server's own cellular opt-in reinstates the fill on a metered link")
  func cellularOptInPlansTheFill() {
    let opted = SyncCondition(
      cost: LinkCost(isExpensive: true, isConstrained: false),
      syncOverCellular: true)
    #expect(SyncPlan.phases(isEntireLibrary: true, condition: opted) == .full)
  }

  @Test("The cheap phases are never dropped, however hostile the link")
  func cheapPhasesAlwaysRun() {
    let worst = SyncCondition(
      cost: LinkCost(isExpensive: true, isConstrained: true), syncOverCellular: true
    )
    let phases = SyncPlan.phases(isEntireLibrary: true, condition: worst)
    #expect(phases.contains(.elements))
    #expect(phases.contains(.reconcile))
    #expect(!phases.contains(.fill))
  }

  @Test("The sweep plans each server by the same rule the active server uses")
  func sweepAgreesWithTheSharedRule() {
    let actions = SyncPlan.inactiveActions(
      connections: [
        snapshot(Self.a, isEntireLibrary: true),
        snapshot(Self.b, isEntireLibrary: true, syncOverCellular: true),
        snapshot(Self.c, isEntireLibrary: false),
      ],
      activeID: nil, lastSweep: [:], now: now, throttle: throttle,
      cost: LinkCost(isExpensive: true, isConstrained: false))

    for action in actions {
      let server = [Self.a: false, Self.b: true, Self.c: false][action.serverID]!
      let expected = SyncPlan.phases(
        isEntireLibrary: action.serverID != Self.c,
        condition: SyncCondition(
          cost: LinkCost(isExpensive: true, isConstrained: false),
          syncOverCellular: server))
      #expect(action.phases == expected)
    }
  }
}

@Suite("Sync phases")
struct SyncPhasesTests {
  @Test("ordered is dependency order regardless of how the set was built")
  func orderedIsCanonical() {
    #expect(SyncPhases([.fill, .elements, .reconcile]).ordered == [.elements, .reconcile, .fill])
    #expect(SyncPhases([.fill, .elements]).ordered == [.elements, .fill])
  }

  @Test("cheap omits the fill, full includes it")
  func presets() {
    #expect(!SyncPhases.cheap.contains(.fill))
    #expect(SyncPhases.cheap.contains(.elements))
    #expect(SyncPhases.cheap.contains(.reconcile))
    #expect(SyncPhases.full.contains(.fill))
    #expect(SyncPhases.nothing.isEmpty)
  }
}
