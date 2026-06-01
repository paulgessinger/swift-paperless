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
  public func clearCache() throws {
    let tables =
      V3_CreateElementCache.multiRowTables
      + V3_CreateElementCache.singletonTables
      + V4_CreateDocumentCache.tables
    try writer.write { db in
      for table in tables {
        try db.execute(sql: "DELETE FROM \(table)")
      }
    }
  }
}
