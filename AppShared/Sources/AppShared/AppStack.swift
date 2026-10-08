//
//  AppStack.swift
//  AppShared
//
//  The process's one database and the two owners layered directly on it.
//

import Foundation
import Persistence
import os

/// The per-process persistence stack: the GRDB connection, the sole
/// ``ConnectionManager`` and the sole ``ServerSessionRegistry``.
///
/// A second set in one process would not see the first one's writes (separate
/// SQLite connections) and would sync the same server twice, so entry points
/// get it from ``AppStackHolder`` instead of building their own.
@MainActor
public final class AppStack {
  public let database: Database
  public let connectionManager: ConnectionManager
  public let sessionRegistry: ServerSessionRegistry

  fileprivate init(database: Database) {
    self.database = database
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

  /// The process's stack, opening the app-group database on first call. Throws
  /// what ``Persistence/Database`` throws.
  public static func shared() throws -> AppStack {
    if let cached {
      return cached
    }
    let stack = AppStack(database: try Database())
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
