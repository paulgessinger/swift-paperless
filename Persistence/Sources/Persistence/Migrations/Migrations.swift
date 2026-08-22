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
///
/// ## Migrations must not depend on application types
///
/// A migration describes a *past* state of the database; the rest of the app
/// targets only the latest one. So a migration may never mention a record type,
/// a `databaseTableName`, a `Columns` constant, or a record's JSON coder — those
/// track the present, and the migration has to keep doing what it did the day it
/// shipped, forever. GRDB states the rule directly: *"migrations should talk to
/// the database, only to the database, and use the database language"*.
///
/// In practice that means **literal table names, literal column lists, literal
/// SQL**, and — for a data migration that writes rows — a frozen local copy of
/// whatever shape it writes (see `V2_ImportLegacyConnections`, which carries its
/// own `V1StoredUser` / `V1StoredHeader`).
///
/// This is not theoretical here. `V2` originally inserted through
/// `ConnectionRecord`; adding `sync_over_cellular` in `V9` made it name a column
/// that does not exist at V2 time, and the migration threw at launch for every
/// user upgrading from before it. Caught by tests, but it would have shipped as
/// an app that refuses to start.
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

    migrator.registerMigration("v3_create_element_cache") { db in
      try V3_CreateElementCache.run(db)
    }

    migrator.registerMigration("v4_create_document_cache") { db in
      try V4_CreateDocumentCache.run(db)
    }

    migrator.registerMigration("v5_create_document_detail_cache") { db in
      try V5_CreateDocumentDetailCache.run(db)
    }

    migrator.registerMigration("v6_drop_projection_and_query_order_fk") { db in
      try V6_DropProjectionAndQueryOrderFK.run(db)
    }

    migrator.registerMigration("v7_create_query_sync_error") { db in
      try V7_CreateQuerySyncError.run(db)
    }

    migrator.registerMigration("v8_add_sync_over_cellular") { db in
      try V8_AddSyncOverCellular.run(db)
    }

    migrator.registerMigration("v9_promote_document_query_columns") { db in
      try V9_PromoteDocumentQueryColumns.run(db)
    }

    return migrator
  }
}
