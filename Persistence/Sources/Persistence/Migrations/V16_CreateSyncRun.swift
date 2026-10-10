import GRDB

/// A record of every sync step the app runs, for diagnosing what a pass did
/// after the fact: which steps ran under which trigger, how they ended, and
/// what they reported. One row per step execution; the steps of one pass share
/// a `run_id`. `server_id` is NULL for rows about a background task as a whole.
///
/// Diagnostic, not cache: deliberately absent from the `tables` lists that
/// `clearCache` wipes, so a cache reset doesn't erase the evidence of why it
/// was needed. Capped per server on insert, cascade-deleted with its `server`.
enum V16_CreateSyncRun {
  static func run(_ db: GRDB.Database) throws {
    try db.create(table: "sync_run", options: [.strict]) { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("run_id", .blob).notNull()
      t.column("server_id", .blob).references("server", onDelete: .cascade)
      t.column("trigger", .text).notNull()
      t.column("step", .text).notNull()
      // `timeIntervalSinceReferenceDate` (REAL), like the other sync stamps.
      t.column("started_at", .real).notNull()
      // NULL while the step runs; a row still open at launch was interrupted.
      t.column("ended_at", .real)
      t.column("outcome", .text)
      t.column("message", .text)
      t.column("succeeded", .integer)
      t.column("failed", .integer)
    }
    try db.create(
      index: "idx_sync_run_server_started", on: "sync_run", columns: ["server_id", "started_at"])
    try db.create(index: "idx_sync_run_run", on: "sync_run", columns: ["run_id"])
  }
}
