//
//  SyncEngine.swift
//  AppShared
//
//  Multi-server sync: keeps every configured server's offline cache
//  warm. The sweep still *selects* the inactive ones — the active server is
//  driven by `DocumentStore` on the same lifecycle trigger, so "active-first"
//  falls out for free — but that is now an ordering choice, not a safety
//  requirement. It used to be both: the store and the engine each built their
//  own `CachingRepository`, so sweeping the active server meant two instances
//  racing the same `query_order` rows, and the engine had to re-check
//  `activeConnectionId` on every iteration to narrow the window. Servers now
//  own their repositories through `ServerSession`, so a sweep that reaches the
//  active server coalesces onto the session the store is already using.
//
//  Foreground app-lifecycle triggers (launch / foreground / active-change)
//  drive `syncInactiveServers`; the background tasks drive
//  `syncServers(scope:tier:...)` through `BackgroundSyncCoordinator` — either
//  against this same instance (registered UI graph) or a headless twin on a
//  cold background launch. The engine deliberately stays `@MainActor` (an
//  earlier note here suggested moving enumeration off-main for background
//  execution — superseded): the main thread runs normally during background
//  execution, and the entire downstream stack (`ConnectionManager`,
//  `CachingRepository`, `CachingBackend`) is main-actor anyway.
//
//  This type is now purely the *scheduler*: it decides which servers to sync and
//  in what order, and hands each one to its ``ServerSession``, which owns that
//  server's repository and runs the sequence. The interesting decisions (scope,
//  throttle, uncredentialed degrade, heavy-fill gating, stalest-first ordering,
//  new-server diff) live in the pure, unit-tested `DataModel.SyncPlan`.
//
//  It keeps no per-server state of its own: freshness stamps and in-flight work
//  live on the sessions, which is what lets a background sweep and the on-screen
//  store agree about a server without either consulting the other.
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
  /// How much work a sweep does per server.
  public enum SyncTier: Sendable {
    /// Elements + reconcile sweeps only — sized for a `BGAppRefreshTask`
    /// budget (~30 s).
    case cheap
    /// Cheap plus the proactive fills where mode and network allow.
    case full
  }

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

  /// The foreground sweep: every inactive server, full tier (active-first is
  /// implicit — active is excluded and driven by the store).
  ///
  /// `userInitiated` bypasses the per-server throttle (explicit "sync now").
  public func syncInactiveServers(
    isExpensive: Bool, isConstrained: Bool, userInitiated: Bool = false
  ) async {
    await syncServers(
      scope: .excludingActive(manager.activeConnectionId), tier: .full,
      isExpensive: isExpensive, isConstrained: isConstrained, userInitiated: userInitiated)
  }

  /// Sweep the servers selected by `scope` once, sequentially (stalest-first),
  /// each isolated so one server's failure never affects the others. Coalesces
  /// concurrent callers: a second caller joins the in-flight sweep whatever its
  /// scope/tier — the end-of-run reschedule (background) or the next lifecycle
  /// trigger (foreground) recovers any work the joined sweep didn't cover.
  ///
  /// `scope: .all` is for the headless background path, where no `DocumentStore`
  /// exists (see `BackgroundSyncCoordinator`). It is no longer a *safety*
  /// distinction — sessions own their repositories, so an in-process sweep that
  /// reaches the active server coalesces onto the store's session rather than
  /// racing it — but it stays the honest description of which servers a
  /// headless run is responsible for.
  public func syncServers(
    scope: SyncPlan.SweepScope, tier: SyncTier, isExpensive: Bool, isConstrained: Bool,
    userInitiated: Bool = false
  ) async {
    if let sweepTask {
      return await sweepTask.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await runSweep(
        scope: scope, tier: tier, isExpensive: isExpensive, isConstrained: isConstrained,
        userInitiated: userInitiated)
    }
    sweepTask = task
    await task.value
    sweepTask = nil
  }

  // MARK: - Sweep

  private func runSweep(
    scope: SyncPlan.SweepScope, tier: SyncTier, isExpensive: Bool, isConstrained: Bool,
    userInitiated: Bool
  ) async {
    let snapshots = manager.connections.values.map { conn in
      SyncPlan.ServerSnapshot(
        id: conn.id,
        hasToken: hasToken(conn),
        isEntireLibrary: conn.offlineBrowsingMode == .entireLibrary,
        syncOverCellular: conn.syncOverCellular)
    }
    // `lastSuccessfulSyncs()` merges the persisted per-server stamps under the
    // sessions' in-memory ones, so ordering stays stalest-first across a cold
    // launch (background wake or fresh process) and a server synced moments
    // before the process died isn't re-swept.
    let actions = SyncPlan.sweepActions(
      connections: snapshots,
      scope: scope,
      lastSweep: userInitiated ? [:] : registry.lastSuccessfulSyncs(),
      now: Date(),
      throttle: inactiveThrottle,
      isExpensive: isExpensive,
      isConstrained: isConstrained,
      includeHeavy: tier == .full)

    Logger.sync.info(
      "Sweep (\(String(describing: scope), privacy: .public), tier: \(String(describing: tier), privacy: .public)): \(actions.count) of \(snapshots.count) server(s) (isExpensive: \(isExpensive), isConstrained: \(isConstrained), userInitiated: \(userInitiated))"
    )
    for action in actions {
      // No "skip the server that went active mid-sweep" guard any more: sweeping
      // it now means driving the *same* `ServerSession` the store drives, which
      // coalesces onto that session's per-phase single-flights instead of racing
      // a second `CachingRepository`. The guard only ever narrowed that window;
      // one owner per server closes it.
      guard let stored = manager.connections[action.serverID] else { continue }
      await runAction(action, stored: stored)
    }
    Logger.sync.info("Sweep complete")
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
