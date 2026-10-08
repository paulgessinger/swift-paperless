import Foundation
import GRDB

/// A read-only look at the database's bookkeeping for the debug menu: row
/// counts, sync cursors and per-list counters. Counts, timestamps and short
/// values only; no document contents.
public struct DatabaseStatistics: Sendable, Equatable {
  /// Migration identifiers applied to this database, in registration order.
  public var appliedMigrations: [String]
  /// Migrations this build registers.
  public var registeredMigrationCount: Int
  /// Copied from ``Database/didEraseForSchemaChangeAtLaunch``.
  public var didEraseForSchemaChangeAtLaunch: Bool

  public var sqliteVersion: String
  public var journalMode: String
  public var pageSize: Int
  public var pageCount: Int
  public var freePageCount: Int
  /// Main file plus `-wal` / `-shm`; zero for an in-memory database.
  public var diskUsageBytes: Int64

  /// Every table in `sqlite_master` except SQLite's internal ones, by name.
  public var tables: [TableRowCount]
  /// One entry per `server` row, ordered by id.
  public var servers: [Server]

  public struct TableRowCount: Sendable, Equatable {
    public var name: String
    public var rows: Int
  }

  public struct Server: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Raw value of AppShared's `OfflineBrowsingMode`.
    public var offlineBrowsingMode: String
    public var syncOverCellular: Bool
    public var needsAuth: Bool
    public var deltaWatermark: Date?
    public var libraryCoverageAt: Date?
    public var lastReconcileAt: Date?
    public var lastSuccessfulSyncAt: Date?
    /// Row counts of every table with a `server_id` column, by table name.
    /// Tables without rows for this server are absent.
    public var rowsByTable: [String: Int]
    /// `query_order` rows with no `document` row.
    public var skeletonRows: Int
    /// `document` rows no `query_order` row references.
    public var unreferencedDocuments: Int
    /// Documents with notes but no cached `document_note` row.
    public var documentsAwaitingNotes: Int
    /// Documents whose current version has no cached `file_metadata` row.
    public var documentsAwaitingFileMetadata: Int
    /// Ordered by key.
    public var queries: [Query]
  }

  /// One cached list: the union of its `query_meta`, `query_order` and
  /// `query_sync_error` rows.
  public struct Query: Sendable, Equatable, Identifiable {
    public var key: QueryKey
    public var id: String { key.rawValue }
    /// `nil` when the list has no `query_meta` row or no recorded total.
    public var totalCount: UInt?
    public var orderRows: Int
    public var lastPosition: Int?
    public var skeletonRows: Int
    /// `query_order` rows whose `placed_modified` is unknown.
    public var unknownPlacementRows: Int
    public var filledAt: Date?
    public var viewedAt: Date?
    public var orderGeneration: Int
    public var orderBasis: Int
    public var syncError: SyncError?

    public var orderStale: Bool { orderGeneration > orderBasis }
  }

  public struct SyncError: Sendable, Equatable {
    /// `nil` for the default list.
    public var savedViewName: String?
    public var message: String
    public var failedAt: Date
  }
}

extension Database {
  /// Gather ``DatabaseStatistics`` in one read transaction, so every count
  /// describes the same snapshot. Scans `query_order` and `document` once each
  /// for the skeleton and backlog counts; meant for an on-demand debug screen,
  /// not for a polling loop.
  ///
  /// Async only, like every cache table — see the rule in `Database+Connections`.
  public func statistics() async throws -> DatabaseStatistics {
    let migrator = Migrations.migrator(legacyConnectionsUserDefaults: nil)
    let erased = didEraseForSchemaChangeAtLaunch
    let diskUsage = diskUsage()
    return try await wrappingAsync("statistics") {
      try await writer.read { db in
        try Self.statistics(db, migrator: migrator, erased: erased, diskBytes: diskUsage.bytes)
      }
    }
  }

  private static func statistics(
    _ db: GRDB.Database, migrator: DatabaseMigrator, erased: Bool, diskBytes: Int64
  ) throws -> DatabaseStatistics {
    let tableNames = try String.fetchAll(
      db,
      sql: """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """)
    var tables: [DatabaseStatistics.TableRowCount] = []
    var rowsByServer: [UUID: [String: Int]] = [:]
    for name in tableNames {
      let quoted = name.quotedDatabaseIdentifier
      let rows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(quoted)") ?? 0
      tables.append(.init(name: name, rows: rows))
      guard try db.columns(in: name).contains(where: { $0.name == "server_id" }) else { continue }
      for row in try Row.fetchAll(
        db, sql: "SELECT server_id, COUNT(*) AS n FROM \(quoted) GROUP BY server_id")
      {
        rowsByServer[row["server_id"], default: [:]][name] = row["n"]
      }
    }

    let skeletons = try groupedCounts(
      db,
      sql: """
        SELECT q.server_id, q.query_key, COUNT(*) AS n FROM query_order q
        LEFT JOIN document d ON d.server_id = q.server_id AND d.id = q.remote_id
        WHERE d.id IS NULL
        GROUP BY q.server_id, q.query_key
        """)
    let unreferenced = try serverCounts(
      db,
      sql: """
        SELECT d.server_id, COUNT(*) AS n FROM document d
        WHERE NOT EXISTS (
          SELECT 1 FROM query_order q WHERE q.server_id = d.server_id AND q.remote_id = d.id)
        GROUP BY d.server_id
        """)
    // Same predicates as `documentIDsNeedingNotes` / `…NeedingFileMetadata`.
    let awaitingNotes = try serverCounts(
      db,
      sql: """
        SELECT d.server_id, COUNT(*) AS n FROM document d
        LEFT JOIN document_note n ON n.server_id = d.server_id AND n.document_id = d.id
        WHERE n.document_id IS NULL AND d.notes_count > 0
        GROUP BY d.server_id
        """)
    let awaitingMetadata = try serverCounts(
      db,
      sql: """
        SELECT d.server_id, COUNT(*) AS n FROM document d
        WHERE NOT EXISTS (
          SELECT 1 FROM file_metadata f
          WHERE f.server_id = d.server_id AND f.version_id = d.current_version_id
            AND (d.modified IS NULL OR f.document_modified IS d.modified))
        GROUP BY d.server_id
        """)

    var queries: [UUID: [String: DatabaseStatistics.Query]] = [:]
    func update(_ serverID: UUID, _ key: String, _ apply: (inout DatabaseStatistics.Query) -> Void)
    {
      var query =
        queries[serverID]?[key]
        ?? DatabaseStatistics.Query(
          key: QueryKey(stored: key), totalCount: nil, orderRows: 0, lastPosition: nil,
          skeletonRows: skeletons[serverID]?[key] ?? 0, unknownPlacementRows: 0,
          filledAt: nil, viewedAt: nil, orderGeneration: 0, orderBasis: 0, syncError: nil)
      apply(&query)
      queries[serverID, default: [:]][key] = query
    }
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT server_id, query_key, total_count, filled_at, viewed_at,
               order_generation, order_basis
        FROM query_meta
        """)
    {
      update(row["server_id"], row["query_key"]) {
        $0.totalCount = row["total_count"]
        $0.filledAt = row["filled_at"]
        $0.viewedAt = row["viewed_at"]
        $0.orderGeneration = row["order_generation"]
        $0.orderBasis = row["order_basis"]
      }
    }
    for row in try Row.fetchAll(
      db,
      sql: """
        SELECT server_id, query_key, COUNT(*) AS n, MAX(position) AS last,
               SUM(placed_modified IS NULL) AS unknown
        FROM query_order GROUP BY server_id, query_key
        """)
    {
      update(row["server_id"], row["query_key"]) {
        $0.orderRows = row["n"]
        $0.lastPosition = row["last"]
        $0.unknownPlacementRows = row["unknown"]
      }
    }
    for row in try Row.fetchAll(
      db,
      sql: "SELECT server_id, query_key, saved_view_name, message, failed_at FROM query_sync_error")
    {
      update(row["server_id"], row["query_key"]) {
        $0.syncError = .init(
          savedViewName: row["saved_view_name"], message: row["message"],
          failedAt: Date(timeIntervalSinceReferenceDate: row["failed_at"]))
      }
    }

    var syncState: [UUID: ServerSyncStateRecord] = [:]
    for record in try ServerSyncStateRecord.fetchAll(db) {
      syncState[record.serverId] = record
    }
    let servers = try ConnectionRecord.order(ConnectionRecord.Columns.id).fetchAll(db).map {
      server in
      let state = syncState[server.id]
      return DatabaseStatistics.Server(
        id: server.id,
        offlineBrowsingMode: server.offlineBrowsingMode,
        syncOverCellular: server.syncOverCellular,
        needsAuth: server.needsAuth,
        deltaWatermark: state?.deltaWatermark.map(Date.init(timeIntervalSinceReferenceDate:)),
        libraryCoverageAt: state?.libraryCoverageAt.map(Date.init(timeIntervalSinceReferenceDate:)),
        lastReconcileAt: state?.lastReconcileAt.map(Date.init(timeIntervalSinceReferenceDate:)),
        lastSuccessfulSyncAt: state?.lastSuccessfulSyncAt.map(
          Date.init(timeIntervalSinceReferenceDate:)),
        rowsByTable: rowsByServer[server.id] ?? [:],
        skeletonRows: skeletons[server.id]?.values.reduce(0, +) ?? 0,
        unreferencedDocuments: unreferenced[server.id] ?? 0,
        documentsAwaitingNotes: awaitingNotes[server.id] ?? 0,
        documentsAwaitingFileMetadata: awaitingMetadata[server.id] ?? 0,
        queries: (queries[server.id] ?? [:]).values.sorted { $0.id < $1.id })
    }

    return DatabaseStatistics(
      appliedMigrations: try migrator.appliedMigrations(db),
      registeredMigrationCount: migrator.migrations.count,
      didEraseForSchemaChangeAtLaunch: erased,
      sqliteVersion: try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "",
      journalMode: try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "",
      pageSize: try Int.fetchOne(db, sql: "PRAGMA page_size") ?? 0,
      pageCount: try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0,
      freePageCount: try Int.fetchOne(db, sql: "PRAGMA freelist_count") ?? 0,
      diskUsageBytes: diskBytes,
      tables: tables,
      servers: servers)
  }

  /// `(server_id, n)` rows as a dictionary.
  private static func serverCounts(_ db: GRDB.Database, sql: String) throws -> [UUID: Int] {
    var counts: [UUID: Int] = [:]
    for row in try Row.fetchAll(db, sql: sql) {
      counts[row["server_id"]] = row["n"]
    }
    return counts
  }

  /// `(server_id, query_key, n)` rows as nested dictionaries.
  private static func groupedCounts(
    _ db: GRDB.Database, sql: String
  ) throws -> [UUID: [String: Int]] {
    var counts: [UUID: [String: Int]] = [:]
    for row in try Row.fetchAll(db, sql: sql) {
      counts[row["server_id"], default: [:]][row["query_key"]] = row["n"]
    }
    return counts
  }
}
