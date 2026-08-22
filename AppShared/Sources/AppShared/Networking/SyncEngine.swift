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
  @ObservationIgnored private let database: Database
  @ObservationIgnored private let manager: ConnectionManager
  @ObservationIgnored private let mode: ApiRepository.Mode
  /// Live raw path cost read for the observation-driven initial-sync path (the
  /// lifecycle-triggered sweep receives it as a parameter instead). Raw, not a
  /// decision — each server combines it with its own `syncOverCellular` via
  /// `SyncCondition`.
  @ObservationIgnored private let pathCost:
    @MainActor () -> (isExpensive: Bool, isConstrained: Bool)

  /// One session per server, retained across sweeps.
  ///
  /// This replaces the parallel `inFlight` / `lastSweep` dictionaries that used
  /// to live here: both were per-server state keyed by UUID, which is precisely
  /// what a session *is*. Retaining them also means a server's repository —
  /// and therefore its `activeFills` dedupe — survives from one sweep to the
  /// next instead of being rebuilt and forgotten each time.
  ///
  /// The active server is never keyed here: it is `DocumentStore`'s to drive.
  @ObservationIgnored private var sessions: [UUID: ServerSession] = [:]
  /// Whole-sweep single-flight, coalescing concurrent lifecycle triggers.
  @ObservationIgnored private var sweepTask: Task<Void, Never>?
  /// Server IDs seen at the last observation tick, to detect newly-added ones.
  @ObservationIgnored private var knownServerIDs: Set<UUID> = []
  @ObservationIgnored private var observationTask: Task<Void, Never>?

  /// Background warmth cadence for inactive servers — deliberately looser than
  /// the active path's 300 s reconcile throttle; these servers aren't on screen.
  @ObservationIgnored private let inactiveThrottle: TimeInterval = 900

  public init(
    database: Database,
    manager: ConnectionManager,
    pathCost: @escaping @MainActor () -> (isExpensive: Bool, isConstrained: Bool),
    mode: ApiRepository.Mode = Bundle.main.appConfiguration.mode
  ) {
    self.database = database
    self.manager = manager
    self.pathCost = pathCost
    self.mode = mode
  }

  deinit {
    observationTask?.cancel()
  }

  // MARK: - Public API

  /// Begin observing the `server` table (via `manager.connections`, which is the
  /// sole projection of it). A newly-appeared, non-active server triggers a
  /// throttle-exempt initial sync.
  ///
  /// This is wired to the *observation*, not the "Add server" UI action, so a
  /// Stage-12 UBKVS `server` upsert flows into the initial-sync path for free.
  /// Removed servers need no cache work — the `server` row delete FK-cascades
  /// the whole cache; the engine just drops their session.
  public func start() {
    guard observationTask == nil else { return }
    // Seed with the current set so the observation only reacts to *new* servers;
    // the servers present at launch are handled by the explicit sweep below.
    knownServerIDs = Set(manager.connections.keys)
    observationTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
          _ = self?.manager.connections.keys
        } onChange: {
          continuation.yield()
          continuation.finish()
        }
        self?.handleConnectionsChanged()
        for await _ in stream { break }
      }
    }
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
      lastSweep: userInitiated ? [:] : lastSuccessfulSyncs(),
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

  private func handleConnectionsChanged() {
    let current = Set(manager.connections.keys)
    // Drop the session of any server whose row vanished (cache already cascaded).
    for id in knownServerIDs.subtracting(current) {
      sessions.removeValue(forKey: id)?.invalidate()
    }
    let added = SyncPlan.newlyAdded(
      current: current, known: knownServerIDs, activeID: manager.activeConnectionId)
    knownServerIDs = current
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
    let session = session(for: stored.id)
    if action.needsAuthOnly {
      session.markNeedsAuth(stored)
      return
    }
    await session.sync(stored: stored, runHeavyFill: action.runHeavyFill)
  }

  // MARK: - Sessions

  /// The server's session, created on first use. Sessions are cheap — a
  /// repository is only assembled when something actually syncs.
  private func session(for id: UUID) -> ServerSession {
    if let existing = sessions[id] {
      return existing
    }
    let session = ServerSession(
      serverID: id, database: database, manager: manager, mode: mode)
    sessions[id] = session
    return session
  }

  /// The throttle input `SyncPlan` consumes, projected out of the sessions.
  private func lastSuccessfulSyncs() -> [UUID: Date] {
    sessions.compactMapValues(\.lastSuccessfulSync)
  }

  // MARK: - Helpers

  /// True only when a non-empty credential is present. `try? … ?? nil` flattens
  /// the double optional so a Keychain read error (`.none`) and an absent token
  /// (`.some(nil)`) both read as "no token" → per-server needs-auth degrade.
  private func hasToken(_ stored: StoredConnection) -> Bool {
    ((try? stored.token) ?? nil) != nil
  }
}
