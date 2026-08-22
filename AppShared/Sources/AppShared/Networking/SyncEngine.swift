//
//  SyncEngine.swift
//  AppShared
//
//  Stage 10 (multi-server sync): keeps every *inactive* configured server's
//  offline cache warm. The active server is deliberately NOT touched here — it
//  is driven by `DocumentStore` (its own `CachingRepository` instance), so the
//  engine skips `activeConnectionId` to avoid two instances racing the same
//  `query_order` rows. "Active-first" therefore falls out for free: the store
//  syncs the active server on the same lifecycle trigger, and the engine sweeps
//  the rest.
//
//  Scheduling stays on app-lifecycle triggers (launch / foreground /
//  active-change); true `BGProcessingTask` execution is Stage 11's.
//
//  This type is now purely the *scheduler*: it decides which servers to sync and
//  in what order, and hands each one to its ``ServerSession``, which owns that
//  server's repository and runs the sequence. The interesting decisions (active
//  exclusion, throttle, uncredentialed degrade, heavy-fill gating, new-server
//  diff) live in the pure, unit-tested `DataModel.SyncPlan`.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import os

@MainActor
@Observable
public final class SyncEngine {
  @ObservationIgnored private let manager: ConnectionManager
  /// Live raw path cost read for the observation-driven initial-sync path (the
  /// lifecycle-triggered sweep receives it as a parameter instead). Raw, not a
  /// decision — each server combines it with its own `syncOverCellular` via
  /// `SyncCondition`.
  @ObservationIgnored private let pathCost:
    @MainActor () -> (isExpensive: Bool, isConstrained: Bool)

  /// Where the per-server sessions live. The engine borrows them; it does not
  /// own them, and it no longer keeps any per-server state of its own.
  @ObservationIgnored private let registry: ServerSessionRegistry
  /// Whole-sweep single-flight, coalescing concurrent lifecycle triggers.
  @ObservationIgnored private var sweepTask: Task<Void, Never>?

  /// Background warmth cadence for inactive servers — deliberately looser than
  /// the active path's 300 s reconcile throttle; these servers aren't on screen.
  @ObservationIgnored private let inactiveThrottle: TimeInterval = 900

  public init(
    registry: ServerSessionRegistry,
    manager: ConnectionManager,
    pathCost: @escaping @MainActor () -> (isExpensive: Bool, isConstrained: Bool)
  ) {
    self.registry = registry
    self.manager = manager
    self.pathCost = pathCost
  }

  // MARK: - Public API

  /// Start reacting to the server table: a newly-appeared, non-active server
  /// gets a throttle-exempt initial sync.
  ///
  /// The observation itself belongs to ``ServerSessionRegistry`` — it owns
  /// session lifetime, and one observer of that table is the whole point. The
  /// engine only supplies the *policy* for what an addition deserves.
  public func start() {
    registry.onServersChanged = { [weak self] current, previous in
      self?.handleServersChanged(current: current, previous: previous)
    }
    registry.start()
  }

  /// Sweep every inactive server once, sequentially (active-first is implicit —
  /// active is excluded and driven by the store), each isolated so one server's
  /// failure never affects the others. Coalesces concurrent callers.
  ///
  /// `userInitiated` bypasses the per-server throttle (explicit "sync now").
  public func syncInactiveServers(
    isExpensive: Bool, isConstrained: Bool, userInitiated: Bool = false
  ) async {
    if let sweepTask {
      return await sweepTask.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await runSweep(
        isExpensive: isExpensive, isConstrained: isConstrained, userInitiated: userInitiated)
    }
    sweepTask = task
    await task.value
    sweepTask = nil
  }

  // MARK: - Sweep

  private func runSweep(isExpensive: Bool, isConstrained: Bool, userInitiated: Bool) async {
    let snapshots = manager.connections.values.map { conn in
      SyncPlan.ServerSnapshot(
        id: conn.id,
        hasToken: hasToken(conn),
        isEntireLibrary: conn.offlineBrowsingMode == .entireLibrary,
        syncOverCellular: conn.syncOverCellular)
    }
    let actions = SyncPlan.inactiveActions(
      connections: snapshots,
      activeID: manager.activeConnectionId,
      lastSweep: userInitiated ? [:] : registry.lastSuccessfulSyncs(),
      now: Date(),
      throttle: inactiveThrottle,
      isExpensive: isExpensive,
      isConstrained: isConstrained)

    Logger.sync.info(
      "Inactive sweep: \(actions.count) of \(snapshots.count) server(s) (isExpensive: \(isExpensive), isConstrained: \(isConstrained), userInitiated: \(userInitiated))"
    )
    for action in actions {
      // Re-read per iteration: the action list was computed before the first
      // `await`, so a server the user switched to mid-sweep would otherwise be
      // swept here while `DocumentStore` drives it on the same server.
      guard action.serverID != manager.activeConnectionId else { continue }
      guard let stored = manager.connections[action.serverID] else { continue }
      await runAction(action, stored: stored)
    }
    Logger.sync.info("Inactive sweep complete")
  }

  /// Policy for a server that just appeared. Session creation and teardown
  /// already happened in the registry; all that is left is deciding what the
  /// addition deserves, which is `SyncPlan`'s call.
  private func handleServersChanged(current: Set<UUID>, previous: Set<UUID>) {
    let added = SyncPlan.newlyAdded(
      current: current, known: previous, activeID: manager.activeConnectionId)
    if !added.isEmpty {
      Logger.sync.info("Observed \(added.count) new server(s); kicking initial sync")
    }
    for id in added {
      guard let stored = manager.connections[id] else { continue }
      // Throttle-exempt initial sync for a freshly-appeared server.
      let cost = pathCost()
      let condition = SyncCondition(
        isExpensive: cost.isExpensive, isConstrained: cost.isConstrained,
        syncOverCellular: stored.syncOverCellular)
      let action = SyncServerAction(
        serverID: stored.id,
        needsAuthOnly: !hasToken(stored),
        runHeavyFill: condition.allowsProactiveSync && stored.offlineBrowsingMode == .entireLibrary)
      Task { @MainActor [weak self] in await self?.runAction(action, stored: stored) }
    }
  }

  // MARK: - Per-server execution

  private func runAction(_ action: SyncServerAction, stored: StoredConnection) async {
    let session = registry.session(for: stored.id)
    if action.needsAuthOnly {
      session.markNeedsAuth(stored)
      return
    }
    await session.sync(stored: stored, runHeavyFill: action.runHeavyFill)
  }

  // MARK: - Helpers

  /// True only when a non-empty credential is present. `try? … ?? nil` flattens
  /// the double optional so a Keychain read error (`.none`) and an absent token
  /// (`.some(nil)`) both read as "no token" → per-server needs-auth degrade.
  private func hasToken(_ stored: StoredConnection) -> Bool {
    ((try? stored.token) ?? nil) != nil
  }
}
