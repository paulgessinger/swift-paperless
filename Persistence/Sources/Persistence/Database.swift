import Common
import Foundation
import GRDB
import os

/// Owns the single shared GRDB connection for the app process.
///
/// The on-disk SQLite file lives in the app-group container at
/// `<container>/Library/Application Support/Database/swift-paperless.sqlite`
/// so the main app and the Share Extension can both read it; on iOS the file
/// and its `-wal` / `-shm` sidecars are protected with
/// `.completeUntilFirstUserAuthentication` so BGTasks and the Share Extension
/// can open the DB on a locked device (after first unlock).
///
/// One ``Database`` per process. The shared ``DatabaseWriter`` is GRDB's
/// thread-safe entry point — wrap it in higher-level types (records, the
/// `ConnectionManager` cache) rather than handing the writer out widely.
public final class Database: Sendable {
  /// GRDB connection. `DatabasePool` for on-disk databases (WAL),
  /// `DatabaseQueue` for in-memory test seams. Both conform to ``DatabaseWriter``.
  public let writer: any DatabaseWriter

  // MARK: - Init

  /// Production initializer. Opens (or creates) the app-group SQLite file.
  public convenience init(appGroupIdentifier: String = ContentStore.appGroup) throws {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    else {
      throw DatabaseError.appGroupUnavailable(identifier: appGroupIdentifier)
    }
    let directory =
      container
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("Database", isDirectory: true)
    try Self.createDirectory(directory)
    let url = directory.appendingPathComponent("swift-paperless.sqlite")
    try self.init(
      path: url,
      legacyConnectionsUserDefaults: UserDefaults(suiteName: appGroupIdentifier))
  }

  /// Test seam: explicit on-disk path.
  ///
  /// - Parameter legacyConnectionsUserDefaults: `UserDefaults` to read the
  ///   pre-Stage-5 `[UUID: StoredConnection]` payload from during the v2
  ///   import migration. Pass `nil` (the default) when no legacy data is in
  ///   play; the production convenience initializer threads through the
  ///   app-group suite.
  public init(
    path: URL,
    legacyConnectionsUserDefaults: UserDefaults? = nil
  ) throws {
    let directory = path.deletingLastPathComponent()
    try Self.createDirectory(directory)

    var config = Configuration()
    config.label = "swift-paperless.persistence"
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA journal_mode = WAL;")
      try db.execute(sql: "PRAGMA synchronous = NORMAL;")
      try db.execute(sql: "PRAGMA busy_timeout = 5000;")
      try db.execute(sql: "PRAGMA foreign_keys = ON;")
    }

    let pool: DatabasePool
    do {
      pool = try DatabasePool(path: path.path, configuration: config)
    } catch {
      throw DatabaseError.openFailed(path: path.path, underlying: error)
    }
    self.writer = pool

    // Apply file protection to the directory and to any GRDB sidecar files
    // that exist (the -wal / -shm files appear on first WAL transaction).
    Self.applyFileProtection(directory)
    Self.applyFileProtection(path)
    Self.applyFileProtection(path.deletingPathExtension().appendingPathExtension("sqlite-wal"))
    Self.applyFileProtection(path.deletingPathExtension().appendingPathExtension("sqlite-shm"))

    do {
      try Migrations.migrator(legacyConnectionsUserDefaults: legacyConnectionsUserDefaults)
        .migrate(pool)
    } catch {
      throw DatabaseError.migrationFailed(underlying: error)
    }
  }

  /// In-memory test seam. Uses `DatabaseQueue` because `DatabasePool` requires
  /// a real on-disk file (it relies on WAL).
  ///
  /// - Parameter legacyConnectionsUserDefaults: optional `UserDefaults`
  ///   for the v2 import migration. Default `nil` skips the import — the
  ///   common case for schema / record unit tests.
  public static func inMemory(
    legacyConnectionsUserDefaults: UserDefaults? = nil
  ) throws -> Database {
    var config = Configuration()
    config.label = "swift-paperless.persistence.inMemory"
    config.prepareDatabase { db in
      try db.execute(sql: "PRAGMA foreign_keys = ON;")
    }
    let queue: DatabaseQueue
    do {
      queue = try DatabaseQueue(configuration: config)
    } catch {
      throw DatabaseError.openFailed(path: ":memory:", underlying: error)
    }
    do {
      try Migrations.migrator(legacyConnectionsUserDefaults: legacyConnectionsUserDefaults)
        .migrate(queue)
    } catch {
      throw DatabaseError.migrationFailed(underlying: error)
    }
    return Database(writer: queue)
  }

  /// Private init used only by ``inMemory()``.
  private init(writer: any DatabaseWriter) {
    self.writer = writer
  }

  // MARK: - Destructive maintenance

  /// Delete the on-disk SQLite file and its WAL/SHM sidecars for the given
  /// app group. Intended for the corruption-recovery UI: after a failed
  /// bootstrap, the user can opt in to wiping the local database so the next
  /// bootstrap starts from a clean slate (and re-runs all migrations,
  /// including the v2 import from the app-group `UserDefaults` safety net).
  ///
  /// Callers must not hold a live ``Database`` instance against the same
  /// path when invoking this — there should be no open `DatabasePool` for
  /// the file being deleted.
  public static func wipe(appGroupIdentifier: String = ContentStore.appGroup) throws {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    else {
      throw DatabaseError.appGroupUnavailable(identifier: appGroupIdentifier)
    }
    let base =
      container
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("Database", isDirectory: true)
      .appendingPathComponent("swift-paperless.sqlite")
    let files = [
      base,
      base.deletingPathExtension().appendingPathExtension("sqlite-wal"),
      base.deletingPathExtension().appendingPathExtension("sqlite-shm"),
    ]
    for file in files where FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.removeItem(at: file)
    }
    Logger.persistence.notice("Wiped local database at \(base.path, privacy: .public)")
  }

  // MARK: - Filesystem helpers

  private static func createDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    applyFileProtection(url)
  }

  private static func applyFileProtection(_ url: URL) {
    #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS) || targetEnvironment(macCatalyst)
      guard FileManager.default.fileExists(atPath: url.path) else { return }
      do {
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: url.path)
      } catch {
        Logger.persistence.debug(
          "Could not set file protection on \(url.path, privacy: .public): \(error)"
        )
      }
    #endif
  }
}

public enum DatabaseError: Error {
  case appGroupUnavailable(identifier: String)
  case openFailed(path: String, underlying: Error)
  case migrationFailed(underlying: Error)
}
