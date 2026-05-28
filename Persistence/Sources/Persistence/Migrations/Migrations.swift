import GRDB

/// Registers all GRDB migrations for the swift-paperless database.
///
/// Migrations are forward-only and identified by stable string keys. The
/// migrator's internal `grdb_migrations` table tracks which identifiers
/// have been applied, so re-running the migrator on every `Database.init`
/// is a no-op once a migration has succeeded. The set grows as new tables
/// / columns and one-time data imports are introduced in later stages of
/// the offline-cache plan.
enum Migrations {
  static func migrator() -> DatabaseMigrator {
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

    return migrator
  }
}
