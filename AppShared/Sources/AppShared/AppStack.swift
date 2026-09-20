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
/// ``ConnectionManager`` projecting the `server` table, and the sole
/// ``ServerSessionRegistry`` owning one session per server.
///
/// These three belong together because their invariants are stated in terms of
/// each other, and each one is documented as being *the* one of its kind:
/// ``Persistence/Database`` says one per process, and ``ServerSessionRegistry``
/// says it must be the only observer of `manager.connections`, because two
/// registries keyed by the same UUIDs drift apart. Handing them out separately
/// is what lets a second entry point quietly build a second set.
///
/// A second set is not a tidiness problem, it is a correctness one. Two
/// `DatabasePool`s on one file — even inside a single process — are two
/// independent SQLite connections: GRDB's `ValueObservation` is driven by the
/// update hook on its own connection, so neither sees the other's writes and
/// the element projections silently stop repainting. The single-flight in
/// `ServerSession.syncElements` and the `reconcileSlot` dedupe *within* a
/// session, so two registries mean the same server syncs twice at once,
/// contending for the writer lock with a 5 s `busy_timeout` behind it. And two
/// `ConnectionManager`s each cache the `server` rows in memory, so a token
/// refresh or a `needsAuth` flag written by one is invisible to the other for
/// the lifetime of the process.
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
/// every later caller.
///
/// Every entry point goes through here — the app's scene, the Share Extension,
/// and the App Intents, which matter most: an intent declared in the app target
/// runs *in the app's process*, and `@main` constructs the scene's bootstrap on
/// every launch including the background launch the system does to run an
/// intent. An intent that built its own stack would therefore open a second
/// database on every single run, never on a process of its own.
@MainActor
public enum AppStackHolder {
  /// Only ever holds a stack over the real on-disk database. The in-memory
  /// fallback below is deliberately not cached: it exists so a process with an
  /// unusable app-group container still renders its "no server" state instead
  /// of crashing, and caching that would make one transient failure outlive the
  /// condition that caused it.
  private static var cached: AppStack?

  /// The process's stack, opening the app-group database on first call.
  ///
  /// Throws what ``Persistence/Database`` throws, so a caller that has UI for
  /// the failure — the app — can show it.
  public static func shared() throws -> AppStack {
    if let cached {
      return cached
    }
    let stack = AppStack(database: try Database())
    cached = stack
    return stack
  }

  /// The process's stack, degrading to an in-memory database rather than
  /// throwing. For the entry points with nowhere to show a bootstrap failure:
  /// the Share Extension and the App Intents both have to answer *something*,
  /// and an empty database answers "no server is configured", which is both
  /// true enough and actionable.
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
        // `preconditionFailure` carries only its message into the crash report,
        // so log the underlying error first or the report is undiagnosable.
        Logger.shared.fault(
          "\(context, privacy: .public) in-memory database fallback also failed: \(error)")
        preconditionFailure("In-memory database fallback also failed: \(error)")
      }
    }
  }

  /// Drop the cached stack so the next ``shared()`` rebuilds it. The retry
  /// affordance on the bootstrap failure screen needs this, and so does the
  /// wipe behind it: after `Database.wipe()` the cached stack points at a file
  /// that is no longer there.
  public static func reset() {
    cached = nil
  }
}
