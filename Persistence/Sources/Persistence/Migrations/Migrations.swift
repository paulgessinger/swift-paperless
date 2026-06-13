import Foundation
import GRDB

/// Registers all GRDB migrations — schema and one-time data migrations —
/// for the swift-paperless database.
///
/// Migrations are forward-only and identified by stable string keys. The
/// migrator's internal `grdb_migrations` table tracks which identifiers
/// have been applied, so re-running the migrator on every `Database.init`
/// is a no-op once a migration has succeeded. Schema and data migrations
/// share the same tracking system per the GRDB convention.
enum Migrations {
  /// Build a migrator parameterised by the legacy `UserDefaults` to read
  /// from during the v2 connection import.
  ///
  /// - Parameter legacyConnectionsUserDefaults: app-group `UserDefaults` for
  ///   production callers, an injected suite for importer tests, or `nil`
  ///   for in-memory test seams that have no legacy data to import.
  static func migrator(legacyConnectionsUserDefaults: UserDefaults?) -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
      // Convenience for local development — never enabled in release.
      // Wipes the database when a registered migration's identifier changes,
      // which is appropriate while a migration is still being authored.
      // Once shipped, migrations are immutable.
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1_create_server") { db in
      try V1_CreateServer.run(db)
    }

    // UserDefaults is documented as thread-safe but is not formally marked
    // Sendable. nonisolated(unsafe) captures it into the @Sendable migration
    // closure; the closure only ever passes it to UserDefaults.object(forKey:)
    // which is safe.
    nonisolated(unsafe) let userDefaults = legacyConnectionsUserDefaults
    migrator.registerMigration(V2_ImportLegacyConnections.identifier) { db in
      try V2_ImportLegacyConnections.run(db, userDefaults: userDefaults)
    }

    return migrator
  }
}
