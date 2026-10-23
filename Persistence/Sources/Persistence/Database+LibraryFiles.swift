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
  /// The documents kept offline, whatever the server's mode.
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

  /// A fresh archive for the document's current version, correlated on `d`.
  private static let freshArchiveExists = """
    EXISTS (
      SELECT 1 FROM file f
      WHERE f.server_id = d.server_id
        AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
        AND f.kind = 'archive'
        AND f.modified IS d.modified
    )
    """

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
            NOT \(freshArchiveExists) AS needs_archive,
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
        WHERE d.server_id = ? AND d.modified IS NOT NULL
        """
      case .keptOffline:
        """
        SELECT COUNT(*) AS total,
          COUNT(f.version_id) AS downloaded,
          COALESCE(SUM(f.size), 0) AS bytes
        FROM kept_offline k
        LEFT JOIN document d ON d.server_id = k.server_id AND d.id = k.document_id
        LEFT JOIN file f
          ON f.server_id = d.server_id
          AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
          AND f.kind = 'archive'
          AND f.modified IS d.modified
          AND d.modified IS NOT NULL
        WHERE k.server_id = ?
        """
      }
    let row = try Row.fetchOne(db, sql: sql, arguments: [serverID])
    guard let row else { return .zero }
    return LibraryFileProgress(
      totalDocuments: row["total"], downloadedFiles: row["downloaded"],
      downloadedBytes: row["bytes"])
  }
}
