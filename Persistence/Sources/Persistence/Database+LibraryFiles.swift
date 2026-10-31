import Common
import DataModel
import Foundation
import GRDB

/// A cached document whose current version is missing an archive fetched
/// against its `modified`, or a thumbnail: what the library's file pass
/// downloads.
public struct LibraryFileCandidate: Sendable, Equatable {
  public let documentID: UInt
  /// The version the files are filed under in the content store.
  public let versionID: UInt
  /// The version to put in the request, `nil` when the server reports none.
  public let versionQueryID: UInt?
  public let modified: Date
  /// The files to download, archive first.
  public let kinds: [ContentStore.Kind]

  public init(
    documentID: UInt, versionID: UInt, versionQueryID: UInt?, modified: Date,
    kinds: [ContentStore.Kind]
  ) {
    self.documentID = documentID
    self.versionID = versionID
    self.versionQueryID = versionQueryID
    self.modified = modified
    self.kinds = kinds
  }
}

/// Which documents the file pass downloads for a server.
public enum LibraryFileScope: Sendable, Equatable {
  /// Every cached document: a server in *Entire library*.
  case library
  /// The documents kept offline, on their own or by a kept saved view,
  /// whatever the server's mode.
  case keptOffline
}

/// How much of a scope has its archive on the device, from the index, so the
/// figure survives a relaunch.
public struct LibraryFileProgress: Sendable, Equatable {
  /// For the library, the cached documents with a `modified` to validate a
  /// file against; for the kept documents, every member, cached or not.
  public var totalDocuments: Int
  /// Documents whose current version has a fresh archive row.
  public var downloadedFiles: Int
  public var downloadedBytes: Int64

  public init(totalDocuments: Int = 0, downloadedFiles: Int = 0, downloadedBytes: Int64 = 0) {
    self.totalDocuments = totalDocuments
    self.downloadedFiles = downloadedFiles
    self.downloadedBytes = downloadedBytes
  }

  public static let zero = LibraryFileProgress()
}

/// The library's files: which documents still need their archive or
/// thumbnail, and how far the pass has come. Async only, like every cache
/// table.
extension Database {
  /// The documents whose current version has no fresh archive or no
  /// thumbnail, highest id first: ingestion order, which is what the pass wants, and what paperless
  /// itself orders by (`added` can disagree after an import that kept its
  /// timestamps, and only the order of a pass that downloads everything
  /// depends on it). Documents without `modified` are left out: a file for
  /// them could never be validated. `excluding` holds the documents already
  /// downloading.
  public func documentsNeedingFiles(
    serverID: UUID, scope: LibraryFileScope, excluding: Set<UInt> = [], limit: Int
  ) async throws -> [LibraryFileCandidate] {
    try await wrappingAsync("documentsNeedingFiles") {
      try await writer.read { db in
        try Self.documentsNeedingFiles(
          serverID: serverID, scope: scope, limit: limit + excluding.count, db
        )
        .filter { !excluding.contains($0.record.id) }
        .prefix(limit)
        .map { record, kinds in
          let document = record.domain
          return LibraryFileCandidate(
            documentID: record.id, versionID: document.currentVersionID,
            versionQueryID: document.versionQueryID, modified: record.modified ?? Date(),
            kinds: kinds)
        }
      }
    }
  }

  /// The documents whose current version has no text fetched against its
  /// `modified`, highest id first like ``documentsNeedingFiles(serverID:scope:excluding:limit:)``,
  /// and below `below` when given: a pass walks down from the last id it
  /// asked for, so a document whose text did not become fresh is not asked
  /// for again until the next pass. Every candidate's `kinds` is `[.content]`.
  public func documentsNeedingContent(
    serverID: UUID, scope: LibraryFileScope, below: UInt? = nil, limit: Int
  ) async throws -> [LibraryFileCandidate] {
    try await wrappingAsync("documentsNeedingContent") {
      try await writer.read { db in
        try DocumentRecord.fetchAll(
          db,
          sql: """
            SELECT d.* FROM document d
            WHERE \(Self.needsContent(scope))
              AND d.id < ?
            ORDER BY id DESC
            LIMIT ?
            """,
          arguments: [serverID, below.map(Int64.init) ?? .max, limit]
        ).map { record in
          let document = record.domain
          return LibraryFileCandidate(
            documentID: record.id, versionID: document.currentVersionID,
            versionQueryID: document.versionQueryID, modified: record.modified ?? Date(),
            kinds: [.content])
        }
      }
    }
  }

  /// How many documents ``documentsNeedingContent(serverID:scope:below:limit:)``
  /// would list in all.
  public func countDocumentsNeedingContent(serverID: UUID, scope: LibraryFileScope)
    async throws -> Int
  {
    try await wrappingAsync("countDocumentsNeedingContent") {
      try await writer.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM document d WHERE \(Self.needsContent(scope))",
          arguments: [serverID]) ?? 0
      }
    }
  }

  /// The documents with a fresh archive, and their bytes, against all in the
  /// scope.
  public func libraryFileProgress(serverID: UUID, scope: LibraryFileScope)
    async throws -> LibraryFileProgress
  {
    try await wrappingAsync("libraryFileProgress") {
      try await writer.read { db in
        try Self.libraryFileProgress(serverID: serverID, scope: scope, db)
      }
    }
  }

  /// How much of each kept saved view has its archive on the device, keyed by
  /// saved-view id. A view never synced has no members yet.
  public func keptOfflineViewProgress(serverID: UUID) async throws -> [UInt: LibraryFileProgress] {
    try await wrappingAsync("keptOfflineViewProgress") {
      try await writer.read { db in try Self.keptOfflineViewProgress(serverID: serverID, db) }
    }
  }

  /// Live ``keptOfflineViewProgress(serverID:)``.
  public func observeKeptOfflineViewProgress(serverID: UUID)
    -> AsyncThrowingStream<[UInt: LibraryFileProgress], Error>
  {
    let observation =
      ValueObservation
      .tracking { db in try Self.keptOfflineViewProgress(serverID: serverID, db) }
      .removeDuplicates()
    return stream(observation)
  }

  /// Live ``libraryFileProgress(serverID:scope:)`` for the Offline & Sync screen.
  public func observeLibraryFileProgress(serverID: UUID, scope: LibraryFileScope)
    -> AsyncThrowingStream<LibraryFileProgress, Error>
  {
    let observation =
      ValueObservation
      .tracking { db in try Self.libraryFileProgress(serverID: serverID, scope: scope, db) }
      .removeDuplicates()
    return stream(observation)
  }

  // MARK: - Query bodies

  /// A file of `kind` fetched against the document's `modified`, for its
  /// current version, correlated on `d`.
  private static func freshFileExists(_ kind: ContentStore.Kind) -> String {
    """
    EXISTS (
      SELECT 1 FROM file f
      WHERE f.server_id = d.server_id
        AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
        AND f.kind = '\(kind.rawValue)'
        AND f.modified IS d.modified
    )
    """
  }

  /// A thumbnail for the document's current version, correlated on `d`. Any
  /// row will do: the image cache records its own without a `modified`.
  private static let thumbnailExists = """
    EXISTS (
      SELECT 1 FROM file f
      WHERE f.server_id = d.server_id
        AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
        AND f.kind = 'thumbnail'
    )
    """

  /// A document of the server bound first whose text is missing or stale,
  /// on `document d`.
  private static func needsContent(_ scope: LibraryFileScope) -> String {
    """
    d.server_id = ?
      AND d.modified IS NOT NULL
      \(scopeClause(scope))
      AND NOT \(freshFileExists(.content))
    """
  }

  /// The scope's restriction on `document d`; the library has none.
  private static func scopeClause(_ scope: LibraryFileScope) -> String {
    switch scope {
    case .library: ""
    case .keptOffline: "AND \(keptOfflineExists)"
    }
  }

  private static func documentsNeedingFiles(
    serverID: UUID, scope: LibraryFileScope, limit: Int, _ db: GRDB.Database
  ) throws -> [(record: DocumentRecord, kinds: [ContentStore.Kind])] {
    try Row.fetchAll(
      db,
      sql: """
        SELECT * FROM (
          SELECT d.*,
            NOT \(freshFileExists(.archive)) AS needs_archive,
            NOT \(thumbnailExists) AS needs_thumbnail
          FROM document d
          WHERE d.server_id = ?
            AND d.modified IS NOT NULL
            \(scopeClause(scope))
        )
        WHERE needs_archive OR needs_thumbnail
        ORDER BY id DESC
        LIMIT ?
        """,
      arguments: [serverID, limit]
    ).map { row in
      var kinds: [ContentStore.Kind] = []
      if row["needs_archive"] { kinds.append(.archive) }
      if row["needs_thumbnail"] { kinds.append(.thumbnail) }
      return (try DocumentRecord(row: row), kinds)
    }
  }

  /// The fresh archive of a member's `document d`, if it has one; a member
  /// without a row or a `modified` joins nothing.
  private static let keptArchiveJoin = """
    LEFT JOIN file f
      ON f.server_id = d.server_id
      AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
      AND f.kind = 'archive'
      AND f.modified IS d.modified
      AND d.modified IS NOT NULL
    """

  private static func keptOfflineViewProgress(
    serverID: UUID, _ db: GRDB.Database
  ) throws -> [UInt: LibraryFileProgress] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT v.saved_view_id AS view_id,
          COUNT(k.document_id) AS total,
          COUNT(f.version_id) AS downloaded,
          COALESCE(SUM(f.size), 0) AS bytes
        FROM kept_offline_view v
        LEFT JOIN kept_offline k
          ON k.server_id = v.server_id AND k.saved_view_id = v.saved_view_id
        LEFT JOIN document d ON d.server_id = k.server_id AND d.id = k.document_id
        \(keptArchiveJoin)
        WHERE v.server_id = ?
        GROUP BY v.saved_view_id
        """,
      arguments: [serverID])
    var progress: [UInt: LibraryFileProgress] = [:]
    for row in rows {
      progress[row["view_id"]] = LibraryFileProgress(
        totalDocuments: row["total"], downloadedFiles: row["downloaded"],
        downloadedBytes: row["bytes"])
    }
    return progress
  }

  private static func libraryFileProgress(
    serverID: UUID, scope: LibraryFileScope, _ db: GRDB.Database
  ) throws -> LibraryFileProgress {
    // The kept scope starts from the membership so a member without a row, or
    // without a `modified`, counts as missing; the library from the rows that
    // can be validated.
    let sql =
      switch scope {
      case .library:
        """
        SELECT COUNT(*) AS total,
          COUNT(f.version_id) AS downloaded,
          COALESCE(SUM(f.size), 0) AS bytes
        FROM document d
        LEFT JOIN file f
          ON f.server_id = d.server_id
          AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
          AND f.kind = 'archive'
          AND f.modified IS d.modified
        WHERE d.server_id = :server AND d.modified IS NOT NULL
        """
      case .keptOffline:
        // A document kept on its own and by a view counts once.
        """
        WITH kept(document_id) AS (
          SELECT DISTINCT document_id FROM kept_offline WHERE server_id = :server
        )
        SELECT COUNT(*) AS total,
          COUNT(f.version_id) AS downloaded,
          COALESCE(SUM(f.size), 0) AS bytes
        FROM kept k
        LEFT JOIN document d ON d.server_id = :server AND d.id = k.document_id
        \(keptArchiveJoin)
        """
      }
    let row = try Row.fetchOne(db, sql: sql, arguments: ["server": serverID])
    guard let row else { return .zero }
    return LibraryFileProgress(
      totalDocuments: row["total"], downloadedFiles: row["downloaded"],
      downloadedBytes: row["bytes"])
  }
}
