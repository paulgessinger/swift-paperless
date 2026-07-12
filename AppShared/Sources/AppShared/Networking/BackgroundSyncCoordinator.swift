//
//  BackgroundSyncCoordinator.swift
//  AppShared
//
//  Stage 11 (background sync): the bridge between the app shell's BGTask
//  handlers (app target only — AppShared stays extension-safe and never
//  imports BackgroundTasks) and the sync machinery.
//
//  The invariant this type exists to protect: **at most one
//  `CachingRepository` per server executes at any time.** A BGTask fires
//  in-process, and the process may or may not already contain the UI object
//  graph:
//
//  - *Warm* (app was foregrounded, then suspended): iOS resumes the same
//    process, including any suspended in-flight sync tasks. The handler must
//    therefore drive the *registered* live objects — same instances, so their
//    single-flight guards coalesce everything and the invariant holds by
//    identity. The active server goes through the registered `DocumentStore`,
//    the rest through the registered `SyncEngine` (active excluded, as in the
//    foreground).
//  - *Cold background launch* (nothing registered): no scene connected, no
//    graph exists — the coordinator builds a headless stack and lets the
//    engine sweep `scope: .all`, safe because it is provably the process's
//    only `CachingRepository` owner.
//  - *Foregrounds mid-headless-run*: `register()` cancels-and-awaits the
//    headless run before the UI graph's own sync kicks, closing the one
//    remaining overlap window.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import os

@MainActor
public final class BackgroundSyncCoordinator {
  public static let shared = BackgroundSyncCoordinator()

  private struct UIGraph {
    let database: Database
    let manager: ConnectionManager
    let syncEngine: SyncEngine
    let store: DocumentStore?
  }

  private var registered: UIGraph?
  private var headlessTask: Task<Bool, Never>?

  private init() {}

  /// Hand the live UI object graph to the coordinator. Called from the app
  /// shell whenever the graph (re)wires itself — repeat calls just refresh the
  /// references. Cancels-and-awaits any in-flight headless run first, so two
  /// stacks never execute concurrently.
  public func register(
    database: Database, manager: ConnectionManager, syncEngine: SyncEngine, store: DocumentStore?
  ) async {
    if let headlessTask {
      Logger.sync.info("UI graph registering; cancelling in-flight headless background sync")
      headlessTask.cancel()
      _ = await headlessTask.value
    }
    registered = UIGraph(database: database, manager: manager, syncEngine: syncEngine, store: store)
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
    let unmetered = await NetworkPathProbe.isUnmetered()
    guard let graph = registered else {
      return await runHeadless(tier: tier, unmetered: unmetered)
    }
    Logger.sync.info(
      "Background run (tier: \(String(describing: tier), privacy: .public), registered graph, unmetered: \(unmetered))"
    )
    // Active server first, via its own store (mirrors the foreground order);
    // `sync()` fire-and-forgets a reconcile, so the explicit call either runs
    // it or joins-by-throttle — the trailing engine sweep gives it time either
    // way.
    if let store = graph.store {
      try? await store.sync()
      await store.reconcileDocuments()
      if tier == .full {
        await store.fillLibraryIfEnabled(unmetered: unmetered)
        await store.fillDocumentDetailsIfEnabled(unmetered: unmetered)
      }
    }
    await graph.syncEngine.syncServers(
      scope: .excludingActive(graph.manager.activeConnectionId),
      tier: tier, unmetered: unmetered)
    let completed = !Task.isCancelled
    Logger.sync.info("Background run finished (completed: \(completed))")
    return completed
  }

  private func runHeadless(tier: SyncEngine.SyncTier, unmetered: Bool) async -> Bool {
    Logger.sync.info(
      "Background run (tier: \(String(describing: tier), privacy: .public), headless, unmetered: \(unmetered))"
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
      let engine = SyncEngine(database: database, manager: manager, isUnmetered: { unmetered })
      await engine.syncServers(scope: .all, tier: tier, unmetered: unmetered)
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
