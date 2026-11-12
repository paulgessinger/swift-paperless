import GRDB

/// Adds how the user signed in to each server to `server`.
///
/// Nullable: rows that predate this migration, including connections imported
/// by `V2`, have no recorded method. The value is the raw string of
/// AppShared's `ConnectionAuthMethod`, so `Persistence` stays free of the enum.
enum V22_AddServerAuthMethod {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server") { t in
      t.add(column: "auth_method", .text)
    }
  }
}
