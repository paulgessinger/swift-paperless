import GRDB

/// Adds the server's last-known API and backend versions to `server`.
///
/// Building a repository reads these instead of probing the server first, so
/// activating a server needs no network. Both are nullable: a row is unseeded
/// until the first probe against it succeeds. `backend_version` is the
/// `X-Version` header as sent, so `Persistence` stays free of Networking's
/// `Version` type.
enum V18_AddServerVersions {
  static func run(_ db: GRDB.Database) throws {
    try db.alter(table: "server") { t in
      t.add(column: "api_version", .integer)
      t.add(column: "backend_version", .text)
    }
  }
}
