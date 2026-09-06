import Foundation
import GRDB

/// Cache-maintenance operations that span the element *and* document caches.
///
/// These deliberately leave `server` (the connection rows) untouched — they
/// wipe only the *derived* cached data, so the configured servers survive a
/// "clear local storage" action and the app re-fills from the network on the
/// next sync / list open.
extension Database {
  /// Delete every cached row across the element and document caches, keeping the
  /// `server` connection rows. The live observations repaint empty immediately.
  ///
  /// All cache tables FK-cascade from `server`, so this is *not* the same as
  /// dropping connections; it clears the caches while the connections remain.
  ///
  /// Async only, like every cache table — see the rule in `Database+Connections`.
  public func clearCache() async throws {
    let tables =
      V3_CreateElementCache.multiRowTables
      + V3_CreateElementCache.singletonTables
      + V4_CreateDocumentCache.tables
      + V5_CreateDocumentDetailCache.tables
      + V6_DropProjectionAndQueryOrderFK.tables
      + V7_CreateQuerySyncError.tables
    try await wrappingAsync("clearCache") {
      try await writer.write { db in
        for table in tables {
          try db.execute(sql: "DELETE FROM \(table)")
        }
      }
    }
  }

  /// Every `(server, version)` pair the cached documents still point at — the
  /// reachable set for a `ContentStore` blob sweep.
  ///
  /// Across *all* servers in one read, deliberately: the blob store is a single
  /// app-group directory shared by every connection, so a per-server answer
  /// could not tell a removed server's leftovers (which are garbage) from
  /// another server's live files (which are not).
  ///
  /// Async only, like every cache table — see the rule in `Database+Connections`.
  public func retainedContentVersions() async throws -> [UUID: Set<UInt>] {
    try await wrappingAsync("retainedContentVersions") {
      try await writer.read { db in
        // Only the *current* version is reachable: downloads are always issued
        // for `Document.currentVersionID` (see `ApiRepository.streamDownload`),
        // so every other version's blob is superseded by definition — including
        // the root version, whose id equals the document id.
        //
        // `NULLIF`/`COALESCE` covers the column's `NOT NULL DEFAULT 0`: a row
        // that somehow carries 0 falls back to the document id, which is the
        // right answer for a document with no versions and a conservative one
        // otherwise (it retains a blob rather than dropping a live file).
        let rows = try Row.fetchAll(
          db,
          sql: """
            SELECT server_id, COALESCE(NULLIF(current_version_id, 0), id) AS version_id
            FROM document
            """)
        var retained: [UUID: Set<UInt>] = [:]
        for row in rows {
          let serverID: UUID = row["server_id"]
          let versionID: UInt = row["version_id"]
          retained[serverID, default: []].insert(versionID)
        }
        return retained
      }
    }
  }
}
