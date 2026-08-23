//
//  BackgroundSyncCoordinator.swift
//  AppShared
//
//  Background sync: the bridge between the app shell's BGTask
//  handlers (app target only — AppShared stays extension-safe and never
//  imports BackgroundTasks) and the sync machinery.
//
//  The invariant this type has to respect: **at most one `CachingRepository`
//  per server executes at any time.** Within a single object graph that is now
//  structural — every server's repository belongs to its `ServerSession`, and
//  concurrent callers coalesce onto that session's single-flights — so both
//  paths below are just "sweep every server with this engine":
//
//  - *Warm* (app was foregrounded, then suspended): iOS resumes the same
//    process, so the handler drives the *registered* engine. Its sweep reaches
//    the active server too; that used to be forbidden, and is now simply the
//    same session the on-screen store is using.
//  - *Cold background launch* (nothing registered): no scene connected, no
//    graph exists, so the coordinator builds a headless stack — its own
//    `Database`, `ConnectionManager` and `ServerSessionRegistry`. That is the
//    only difference between the two paths.
//  - *Foregrounds mid-headless-run*: `register()` still cancels-and-awaits the
//    headless run. Sessions make ownership structural *within* a graph, and a
//    headless run is a second graph with its own registry — so this is the one
//    overlap the type still has to close by hand.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import os

@MainActor
@Observable
public final class BackgroundSyncCoordinator {
  public static let shared = BackgroundSyncCoordinator()

  /// Whether a background-task-driven run is currently executing — surfaced on
  /// the Offline & Sync screen (visible when the user foregrounds the app while
  /// a run is still in flight).
  public private(set) var isRunning = false

  /// What a background run needs from the live graph: the engine to sweep with,
  /// and the manager to read scheduling inputs from. Notably *not* the
  /// `DocumentStore` — the active server is reached through its session like
  /// every other server, so the store has nothing to contribute here.
  private struct UIGraph {
    let manager: ConnectionManager
    let syncEngine: SyncEngine
  }

  @ObservationIgnored private var registered: UIGraph?
  @ObservationIgnored private var headlessTask: Task<Bool, Never>?

  private init() {}

  /// Hand the live UI object graph to the coordinator. Called from the app
  /// shell whenever the graph (re)wires itself — repeat calls just refresh the
  /// references. Cancels-and-awaits any in-flight headless run first, so two
  /// stacks never execute concurrently.
  public func register(manager: ConnectionManager, syncEngine: SyncEngine) async {
    if let headlessTask {
      Logger.sync.info("UI graph registering; cancelling in-flight headless background sync")
      headlessTask.cancel()
      _ = await headlessTask.value
    }
    registered = UIGraph(manager: manager, syncEngine: syncEngine)
  }

  public func unregister() {
    registered = nil
  }

  /// Scheduling input: whether any configured server wants the heavy
  /// processing task. `nil` when no UI graph is registered — callers should
  /// submit the request anyway (the handler no-ops cheaply) rather than open
  /// a headless database just to decide.
  public func hasEntireLibraryServer() -> Bool? {
    registered.map { graph in
      graph.manager.connections.values.contains { $0.offlineBrowsingMode == .entireLibrary }
    }
  }

  /// The `BGAppRefreshTask` body: cheap tier (elements + reconcile sweeps),
  /// all servers. Returns whether the run completed uncancelled.
  public func runRefresh() async -> Bool {
    await run(tier: .cheap)
  }

  /// The `BGProcessingTask` body: cheap tier plus the proactive fills where
  /// mode and network allow.
  public func runProcessing() async -> Bool {
    await run(tier: .full)
  }

  // MARK: - Execution

  private func run(tier: SyncEngine.SyncTier) async -> Bool {
    isRunning = true
    defer { isRunning = false }
    let cost = await NetworkPathProbe.currentCost()
    guard let graph = registered else {
      return await runHeadless(tier: tier, cost: cost)
    }
    Logger.sync.info(
      "Background run (tier: \(String(describing: tier), privacy: .public), registered graph, isExpensive: \(cost.isExpensive), isConstrained: \(cost.isConstrained))"
    )
    // One sweep over every server, active included. The hand-rolled
    // active-server pass that used to lead this — `store.sync()`, then an
    // explicit `reconcileDocuments()`, then a fill gated on the *active*
    // server's cellular setting — existed only because the store owned the
    // active server's repository and the engine was forbidden from touching
    // it. It was a third copy of the sync sequence, with its own ordering and
    // its own gate. Now the engine reaches that server through the very session
    // the store uses, `SyncPlan` applies each server's own cellular setting,
    // and stalest-first ordering puts the servers that actually need the run
    // ahead of the one already on screen.
    await graph.syncEngine.syncServers(
      scope: .all, tier: tier, isExpensive: cost.isExpensive,
      isConstrained: cost.isConstrained)
    let completed = !Task.isCancelled
    Logger.sync.info("Background run finished (completed: \(completed))")
    return completed
  }

  private func runHeadless(
    tier: SyncEngine.SyncTier, cost: (isExpensive: Bool, isConstrained: Bool)
  ) async -> Bool {
    Logger.sync.info(
      "Background run (tier: \(String(describing: tier), privacy: .public), headless, isExpensive: \(cost.isExpensive), isConstrained: \(cost.isConstrained))"
    )
    let task = Task { @MainActor () -> Bool in
      let database: Database
      do {
        database = try Database()
      } catch {
        // Includes pre-first-unlock file protection and a failed migration
        // after an update. Never wipe, never surface UI from back here —
        // `DatabaseBootstrap` remains the sole migration-failure surface; the
        // OS reschedule retries later.
        Logger.sync.error("Headless background sync: cannot open database: \(error)")
        return false
      }
      // The sink is normally installed by the app shell at UI launch; a cold
      // background launch never got there, and untracked traffic would
      // undercount the transfer meter.
      TransferStatistics.install()
      let manager = ConnectionManager(database: database)
      // A headless registry: this process has no `DocumentStore`, so these are
      // the only `ServerSession`s in it and the engine is provably the sole
      // owner of every server's repository. It is deliberately not `start()`ed —
      // nothing edits the server table behind a background run.
      let registry = ServerSessionRegistry(database: database, manager: manager)
      let engine = SyncEngine(registry: registry, manager: manager, pathCost: { cost })
      await engine.syncServers(
        scope: .all, tier: tier, isExpensive: cost.isExpensive, isConstrained: cost.isConstrained)
      TransferStatistics.shared.persist()
      let completed = !Task.isCancelled
      Logger.sync.info("Headless background run finished (completed: \(completed))")
      return completed
    }
    headlessTask = task
    defer { headlessTask = nil }
    // Forward outer cancellation (the BGTask expiration handler cancels the
    // driving task) into the stored task, which `register()` can also cancel.
    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }
}
