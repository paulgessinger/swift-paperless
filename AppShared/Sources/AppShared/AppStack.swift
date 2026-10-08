//
//  AppStack.swift
//  AppShared
//
//  The process's one database and the long-lived objects built on it.
//

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

  /// Lazy, so the Share Extension, which never schedules syncs, does not
  /// start a path monitor.
  public private(set) lazy var networkMonitor = NetworkMonitor()

  public private(set) lazy var syncEngine = SyncEngine(
    registry: sessionRegistry,
    manager: connectionManager,
    // Read live, per sweep, so the engine gates on the link as it is when the
    // work starts.
    linkCost: { [weak self] in self?.networkMonitor.cost ?? .unknown })

  init(database: Database, suspension: DatabaseSuspensionController? = nil) {
    self.database = database
    self.suspension = suspension ?? DatabaseSuspensionController()
    let connectionManager = ConnectionManager(database: database)
    self.connectionManager = connectionManager
    sessionRegistry = ServerSessionRegistry(
      database: database, manager: connectionManager)
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
    let stack = AppStack(database: try Database(), suspension: suspension)
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
