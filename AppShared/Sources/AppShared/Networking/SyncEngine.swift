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
//  Two triggers: app-lifecycle events (launch / foreground / active-change)
//  sweep the inactive servers, and the background tasks sweep every server
//  through ``syncAllServers(allowsFill:cost:)``.
//
//  This type is now purely the *scheduler*: it decides which servers to sync and
//  in what order, and hands each one to its ``ServerSession``, which owns that
//  server's repository and runs the sequence. The interesting decisions (active
//  exclusion, throttle, uncredentialed degrade, heavy-fill gating, new-server
//  diff) live in the pure, unit-tested `DataModel.SyncPlan`.
//
//  It keeps no per-server state of its own: freshness stamps live in the
//  database and in-flight work on the sessions, which is what lets a background sweep and the on-screen
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
  @ObservationIgnored private let manager: ConnectionManager
  /// The current link cost, read live at the moment a sweep runs.
  ///
  /// A supplier rather than a parameter on ``syncInactiveServers(userInitiated:)``:
  /// the engine used to accept the cost from its caller *and* hold this closure
  /// for the observation-driven path, which meant four call sites each reaching
  /// into the same monitor to hand back what the engine could already read —
  /// and two sources that could disagree. Injecting it also keeps the engine
  /// off `NetworkMonitor` directly, so a headless caller can supply a cost that
  /// was measured some other way.
  @ObservationIgnored private let linkCost: @MainActor () -> LinkCost

  /// Where the per-server sessions live. The engine borrows them; it does not
  /// own them, and it no longer keeps any per-server state of its own.
  @ObservationIgnored private let registry: ServerSessionRegistry
  /// Whole-sweep single-flight, coalescing concurrent lifecycle triggers.
  @ObservationIgnored private var sweepTask: Task<Void, Never>?
  @ObservationIgnored private var observationTask: Task<Void, Never>?
  /// Servers this engine has already accounted for, diffed to spot additions.
  @ObservationIgnored private var knownServerIDs: Set<UUID> = []

  /// How long a sweep leaves a refreshed server alone — deliberately looser
  /// than the active path's 300 s reconcile throttle.
  @ObservationIgnored private let sweepThrottle: TimeInterval = 900

  public init(
    registry: ServerSessionRegistry,
    manager: ConnectionManager,
    linkCost: @escaping @MainActor () -> LinkCost
  ) {
    self.registry = registry
    self.manager = manager
    self.linkCost = linkCost
  }

  deinit {
    observationTask?.cancel()
  }

  // MARK: - Public API

  /// Start reacting to the server table: a newly-appeared, non-active server
  /// gets a throttle-exempt initial sync.
  ///
  /// The registry owns session lifetime and remains the sole observer of the
  /// `server` table; the engine observes the set the registry *publishes*, and
  /// supplies only the policy for what an addition deserves. `knownServerIDs`
  /// is the engine's own state — "which servers have I already given an initial
  /// sync" — not a second copy of lifecycle.
  public func start() {
    registry.start()
    guard observationTask == nil else { return }
    // Seed from what is already configured: servers present at launch are
    // covered by the caller's explicit sweep, not by the newly-added path.
    knownServerIDs = registry.serverIDs
    observationTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
          _ = self?.registry.serverIDs
        } onChange: {
          continuation.yield()
          continuation.finish()
        }
        self?.handleServersChanged()
        for await _ in stream { break }
      }
    }
  }

  /// Sweep every inactive server once, sequentially (active-first is implicit —
  /// active is excluded and driven by the store), each isolated so one server's
  /// failure never affects the others. Coalesces concurrent callers.
  ///
  /// There is deliberately no throttle-bypassing "user initiated" sweep. The
  /// only explicit sync control in the app is Offline & Sync's *Sync now*, and
  /// that screen is per-server — it sits directly under that server's mode
  /// picker and cellular toggle — so a button there reaching out to touch the
  /// *other* servers would be the surprising reading. The flag that used to be
  /// here was never passed by anyone, and a caller that had passed it would
  /// have silently lost its intent by joining an in-flight automatic sweep.
  public func syncInactiveServers() async {
    if let sweepTask {
      return await sweepTask.value
    }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await runSweep(
        scope: .excludingActive(manager.activeConnectionId), allowsFill: true, cost: linkCost())
    }
    sweepTask = task
    await task.value
    sweepTask = nil
  }

  /// Sweep every server, the active one included, stalest first. For a
  /// background run, where no `DocumentStore` drives the active server.
  ///
  /// Runs in the caller's task: cancelling it stops the sweep before the next
  /// server. Steps already running on a session are stopped by
  /// ``ServerSessionRegistry/cancelAllWork()``. Not coalesced with
  /// ``syncInactiveServers()``; an overlap joins the sessions' own
  /// single-flights.
  ///
  /// - Parameters:
  ///   - allowsFill: `false` limits every server to the cheap phases.
  ///   - cost: The link cost, measured by the caller.
  /// - Returns: `false` if the sweep was cancelled.
  public func syncAllServers(allowsFill: Bool, cost: LinkCost) async -> Bool {
    await runSweep(scope: .all, allowsFill: allowsFill, cost: cost)
    return !Task.isCancelled
  }

  // MARK: - Sweep

  private func runSweep(scope: SyncPlan.Scope, allowsFill: Bool, cost: LinkCost) async {
    let snapshots = manager.connections.values.map { conn in
      SyncPlan.ServerSnapshot(
        id: conn.id,
        hasToken: hasToken(conn),
        isEntireLibrary: conn.offlineBrowsingMode == .entireLibrary,
        syncOverCellular: conn.syncOverCellular)
    }
    let actions = SyncPlan.actions(
      connections: snapshots,
      scope: scope,
      lastSweep: await registry.lastRefreshes(),
      now: Date(),
      throttle: sweepThrottle,
      cost: cost,
      allowsFill: allowsFill)

    let label = scope == .all ? "Full" : "Inactive"
    Logger.sync.info(
      "\(label, privacy: .public) sweep: \(actions.count) of \(snapshots.count) server(s) (expensive: \(cost.isExpensive), constrained: \(cost.isConstrained), fill allowed: \(allowsFill))"
    )
    for action in actions {
      guard !Task.isCancelled else {
        Logger.sync.info("\(label, privacy: .public) sweep cancelled")
        return
      }
      // No "skip the server that went active mid-sweep" guard any more: sweeping
      // it now means driving the *same* `ServerSession` the store drives, which
      // coalesces onto that session's per-phase single-flights instead of racing
      // a second `CachingRepository`. The guard only ever narrowed that window;
      // one owner per server closes it.
      guard let stored = manager.connections[action.serverID] else { continue }
      await runAction(action, stored: stored)
    }
    Logger.sync.info("\(label, privacy: .public) sweep complete")
  }

  /// Policy for a server that just appeared. Session creation and teardown
  /// already happened in the registry; all that is left is deciding what the
  /// addition deserves, which is `SyncPlan`'s call.
  private func handleServersChanged() {
    let current = registry.serverIDs
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
        phases: SyncPlan.phases(
          isEntireLibrary: stored.offlineBrowsingMode == .entireLibrary,
          condition: SyncCondition(
            cost: linkCost(), syncOverCellular: stored.syncOverCellular)))
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
    await session.sync(stored: stored, phases: action.phases)
  }

  // MARK: - Helpers

  /// True only when a non-empty credential is present. `try? … ?? nil` flattens
  /// the double optional so a Keychain read error (`.none`) and an absent token
  /// (`.some(nil)`) both read as "no token" → per-server needs-auth degrade.
  private func hasToken(_ stored: StoredConnection) -> Bool {
    ((try? stored.token) ?? nil) != nil
  }
}
