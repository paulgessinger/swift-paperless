//
//  AppStack.swift
//  AppShared
//
//  The process's one database and the long-lived objects built on it.
//

import Common
import Foundation
import Persistence
import os

/// The per-process stack: the GRDB connection, the sole ``ConnectionManager``,
/// the sole ``ServerSessionRegistry``, and the sync engine and network monitor
/// on top of them.
///
/// A second set in one process would not see the first one's writes (separate
/// SQLite connections) and would sync the same server twice, so entry points
/// get it from ``AppStackHolder`` instead of building their own.
@MainActor
public final class AppStack {
  public let database: Database
  public let connectionManager: ConnectionManager
  public let sessionRegistry: ServerSessionRegistry
  /// Background work runs inside it, so the database writer is open meanwhile.
  public let suspension: DatabaseSuspensionController
  /// The cached files' index and budget, one for every server's store.
  public let contentReclaimer: ContentReclaimer

  /// Lazy, so the Share Extension, which never schedules syncs, does not
  /// start a path monitor.
  public private(set) lazy var networkMonitor = NetworkMonitor()

  public private(set) lazy var syncEngine = SyncEngine(
    registry: sessionRegistry,
    manager: connectionManager,
    // Read live, per sweep, so the engine gates on the link as it is when the
    // work starts.
    linkCost: { [weak self] in self?.networkMonitor.cost ?? .unknown })

  /// - Parameter contentStore: where downloaded files live; `nil` caches no
  ///   files. Only the on-disk database may be paired with the app-group store:
  ///   an index that does not outlive the process would judge every file on
  ///   disk unaccounted for.
  init(
    database: Database, suspension: DatabaseSuspensionController? = nil,
    contentStore: ContentStore? = nil
  ) {
    self.database = database
    let suspension = suspension ?? DatabaseSuspensionController()
    self.suspension = suspension
    let connectionManager = ConnectionManager(database: database)
    self.connectionManager = connectionManager
    let contentReclaimer = ContentReclaimer(database: database, store: contentStore)
    self.contentReclaimer = contentReclaimer
    let sessionRegistry = ServerSessionRegistry(
      database: database, manager: connectionManager, suspension: suspension,
      contentReclaimer: contentReclaimer)
    self.sessionRegistry = sessionRegistry
    suspension.onExpire = { [weak sessionRegistry] in sessionRegistry?.cancelAllWork() }
    // The rows went with the server; its files are only found by the walk.
    sessionRegistry.onServersRemoved = { _ in
      Task { @MainActor in
        _ = await suspension.performBackgroundWork {
          await contentReclaimer.run(reason: .connectionRemoved)
        }
      }
    }

    // Steps the previous process never finished. Only rows older than this
    // process, so a step this one starts first is left alone.
    let launchedAt = Date()
    Task { @MainActor in
      await suspension.performBackgroundWork {
        do {
          let closed = try await database.closeInterruptedSyncSteps(before: launchedAt)
          if closed > 0 {
            Logger.sync.info("Closed \(closed, privacy: .public) interrupted sync step(s)")
          }
        } catch {
          Logger.sync.debug("Closing interrupted sync steps failed: \(error)")
        }
      }
    }
  }

  /// The once-per-launch content sweep. The app calls it; the Share Extension,
  /// which builds a stack of its own, does not walk the store on every share.
  public func runLaunchMaintenance() {
    Task { @MainActor in
      // Thumbnails moved into the content store; the old cache is dead weight.
      await Task.detached(priority: .utility) { LegacyThumbnailCache.remove() }.value
      _ = await suspension.performBackgroundWork {
        await contentReclaimer.run(reason: .launch)
      }
    }
  }
}

/// Builds the process's ``AppStack`` on first use and hands the same one to
/// every later caller: the scene, the Share Extension and the App Intents,
/// which run in the app's process.
@MainActor
public enum AppStackHolder {
  /// Only holds a stack over the on-disk database; the in-memory fallback is not
  /// cached so a transient failure does not outlive its cause.
  private static var cached: AppStack?

  /// The process's suspension controller. It outlives a failed or reset stack,
  /// and the app attaches it to its lifecycle at launch.
  public static let suspension = DatabaseSuspensionController()

  /// The process's stack, opening the app-group database on first call. Throws
  /// what ``Persistence/Database`` throws.
  public static func shared() throws -> AppStack {
    if let cached {
      return cached
    }
    let stack = AppStack(
      database: try Database(), suspension: suspension, contentStore: try? ContentStore())
    cached = stack
    return stack
  }

  /// The process's stack, falling back to an in-memory database instead of
  /// throwing, for entry points with no UI for a bootstrap failure.
  public static func sharedWithInMemoryFallback(context: String) -> AppStack {
    do {
      return try shared()
    } catch {
      Logger.shared.fault(
        "\(context, privacy: .public) database bootstrap failed (\(error)); falling back to in-memory"
      )
      do {
        return AppStack(database: try Database.inMemory())
      } catch {
        // `preconditionFailure` only puts its message in the crash report.
        Logger.shared.fault(
          "\(context, privacy: .public) in-memory database fallback also failed: \(error)")
        preconditionFailure("In-memory database fallback also failed: \(error)")
      }
    }
  }

  /// Drop the cached stack so the next ``shared()`` rebuilds it, after a failure
  /// or `Database.wipe()`.
  public static func reset() {
    cached = nil
  }
}
