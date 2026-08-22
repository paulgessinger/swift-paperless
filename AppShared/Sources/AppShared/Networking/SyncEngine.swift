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
//  active-change); true `BGProcessingTask` execution is Stage 11's. When that
//  lands, `runSweep`'s server enumeration should move from `manager.connections`
//  (main-actor) to an off-main `database.allConnections()` read.
//
//  The interesting decisions (active exclusion, throttle, uncredentialed
//  degrade, heavy-fill gating, new-server diff) live in the pure, unit-tested
//  `DataModel.SyncPlan`; this type is the imperative shell that executes them.
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
  /// Live "is the link unmetered?" read for the observation-driven initial-sync
  /// path (the lifecycle-triggered sweep receives the flag as a parameter).
  @ObservationIgnored private let isUnmetered: @MainActor () -> Bool

  /// Last successful sweep per server; drives the throttle. The active server is
  /// never keyed here (never swept by the engine).
  @ObservationIgnored private var lastSweep: [UUID: Date] = [:]
  /// Per-server in-flight sync, so an observation-driven initial sync and a
  /// lifecycle sweep for the same server coalesce onto one task.
  @ObservationIgnored private var inFlight: [UUID: Task<Void, Never>] = [:]
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
    isUnmetered: @escaping @MainActor () -> Bool,
    mode: ApiRepository.Mode = Bundle.main.appConfiguration.mode
  ) {
    self.database = database
    self.manager = manager
    self.isUnmetered = isUnmetered
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
  /// Removed servers need no work — the `server` row delete FK-cascades the whole
  /// cache; the engine just drops their throttle/in-flight bookkeeping.
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
  public func syncInactiveServers(unmetered: Bool, userInitiated: Bool = false) async {
    if let sweepTask {
      return await sweepTask.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await runSweep(unmetered: unmetered, userInitiated: userInitiated)
    }
    sweepTask = task
    await task.value
    sweepTask = nil
  }

  // MARK: - Sweep

  private func runSweep(unmetered: Bool, userInitiated: Bool) async {
    let snapshots = manager.connections.values.map { conn in
      SyncPlan.ServerSnapshot(
        id: conn.id,
        hasToken: hasToken(conn),
        isEntireLibrary: conn.offlineBrowsingMode == .entireLibrary)
    }
    let actions = SyncPlan.inactiveActions(
      connections: snapshots,
      activeID: manager.activeConnectionId,
      lastSweep: userInitiated ? [:] : lastSweep,
      now: Date(),
      throttle: inactiveThrottle,
      unmetered: unmetered)

    Logger.sync.info(
      "Inactive sweep: \(actions.count) of \(snapshots.count) server(s) (unmetered: \(unmetered), userInitiated: \(userInitiated))"
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
    // Drop bookkeeping for servers whose rows vanished (cache already cascaded).
    for id in knownServerIDs.subtracting(current) {
      inFlight[id]?.cancel()
      inFlight[id] = nil
      lastSweep[id] = nil
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
      let action = SyncServerAction(
        serverID: stored.id,
        needsAuthOnly: !hasToken(stored),
        runHeavyFill: isUnmetered() && stored.offlineBrowsingMode == .entireLibrary)
      Task { @MainActor [weak self] in await self?.runAction(action, stored: stored) }
    }
  }

  // MARK: - Per-server execution

  private func runAction(_ action: SyncServerAction, stored: StoredConnection) async {
    if action.needsAuthOnly {
      // Config-synced-but-uncredentialed: mark per-server needs-auth and make no
      // network call. Deterministic and cheap; when the token later lands, the
      // next sweep picks it up. The 401 path stays a backstop for a rejected token.
      Logger.sync.info(
        "Server \(stored.logLabel, privacy: .public) uncredentialed; marking needs-auth (no sync)")
      manager.markNeedsAuth(for: stored.id)
      return
    }
    if let existing = inFlight[stored.id] {
      return await existing.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await performServerSync(stored, runHeavyFill: action.runHeavyFill)
    }
    inFlight[stored.id] = task
    await task.value
    inFlight[stored.id] = nil
  }

  /// Mirrors the active path's sequence (`DocumentStore.sync` + `reconcileDocuments`
  /// + `fillLibraryIfEnabled` + `fillDocumentDetailsIfEnabled`) against an
  /// ephemeral per-server backend. The whole body is caught so a per-server
  /// failure (offline, rethrown 401, …) never escapes to sibling servers.
  private func performServerSync(_ stored: StoredConnection, runHeavyFill: Bool) async {
    let id = stored.id
    Logger.sync.info(
      "Syncing inactive server \(stored.logLabel, privacy: .public) (heavyFill: \(runHeavyFill))")
    do {
      let backend = try await makeCachingRepository(
        for: stored, database: database, manager: manager, mode: mode)

      // Cheap tier (always, regardless of metered-ness): element sync + the
      // reconcile sweeps (the last two self-gate on *Entire library*).
      try await NetworkTransfer.$category.withValue(.sync) {
        try await backend.syncElements()
      }
      // Each reconcile sweep carries its own catch, as on the active path
      // (`DocumentStore.reconcileDocuments`): the deletion sweep is the most
      // failure-prone of the three — it fetches the server's entire live id set
      // — and under one shared `try` its failure took the freshness delta, the
      // membership rebuild *and* the heavy fill down with it. Cancellation is
      // the exception: it means the pass as a whole is unwanted, so it stops
      // the remaining sweeps instead of being logged and stepped over.
      var failed = false
      var cancelled = false
      func sweep(_ label: String, _ body: () async throws -> Void) async {
        guard !cancelled else { return }
        do {
          try await body()
        } catch {
          guard !error.isCancellationError else {
            Logger.sync.debug("Reconcile cancelled during \(label, privacy: .public)")
            cancelled = true
            return
          }
          Logger.sync.info(
            "Reconcile sweep \(label, privacy: .public) failed (suppressed): \(error)")
          failed = true
        }
      }
      await NetworkTransfer.$category.withValue(.reconcile) {
        await sweep("deletions") { try await backend.reconcileDocumentDeletions() }
        await sweep("changes") { try await backend.reconcileDocumentChanges() }
        await sweep("membership") { try await backend.reconcileSavedViewMembership() }
      }

      // Heavy tier: only on an unmetered *Entire library* server (SyncPlan gate).
      if runHeavyFill, !cancelled {
        try await NetworkTransfer.$category.withValue(.fill) {
          try await backend.fillLibrary(force: false)
          try await backend.fillDocumentDetails()
        }
      }

      // Advance the throttle only on a *fully* successful pass — a sweep that
      // failed or was called off partway retries on the next trigger.
      guard !failed, !cancelled else {
        Logger.sync.info(
          "Inactive server \(stored.logLabel, privacy: .public) partially synced; throttle not advanced"
        )
        return
      }
      lastSweep[id] = Date()
      Logger.sync.info("Inactive server \(stored.logLabel, privacy: .public) synced")
    } catch {
      Logger.sync.info(
        "Inactive-server sync failed for \(stored.logLabel, privacy: .public) (suppressed): \(error)"
      )
    }
  }

  // MARK: - Helpers

  /// True only when a non-empty credential is present. `try? … ?? nil` flattens
  /// the double optional so a Keychain read error (`.none`) and an absent token
  /// (`.some(nil)`) both read as "no token" → per-server needs-auth degrade.
  private func hasToken(_ stored: StoredConnection) -> Bool {
    ((try? stored.token) ?? nil) != nil
  }
}
