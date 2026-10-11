import Common
import DataModel
import Foundation
import GRDB

/// A cached document whose current version has no archive on the device
/// fetched against its `modified`: what the library's file pass downloads.
public struct LibraryFileCandidate: Sendable, Equatable {
  public let documentID: UInt
  /// The version the file is filed under in the content store.
  public let versionID: UInt
  /// The version to put in the request, `nil` when the server reports none.
  public let versionQueryID: UInt?
  public let modified: Date

  public init(documentID: UInt, versionID: UInt, versionQueryID: UInt?, modified: Date) {
    self.documentID = documentID
    self.versionID = versionID
    self.versionQueryID = versionQueryID
    self.modified = modified
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

/// The library's files: which documents still need their archive, and how far
/// the pass has come. Async only, like every cache table.
extension Database {
  /// The documents whose current version has no fresh archive, highest id
  /// first: ingestion order, which is what the pass wants, and what paperless
  /// itself orders by (`added` can disagree after an import that kept its
  /// timestamps, and only the order of a pass that downloads everything
  /// depends on it). Documents without `modified` are left out: a file for
  /// them could never be validated. `excluding` holds the documents already
  /// downloading.
  public func documentsNeedingArchive(
    serverID: UUID, scope: LibraryFileScope = .library, excluding: Set<UInt> = [], limit: Int
  ) async throws -> [LibraryFileCandidate] {
    try await wrappingAsync("documentsNeedingArchive") {
      try await writer.read { db in
        try Self.documentsNeedingArchive(
          serverID: serverID, scope: scope, limit: limit + excluding.count, db
        )
        .filter { !excluding.contains($0.id) }
        .prefix(limit)
        .map { record in
          let document = record.domain
          return LibraryFileCandidate(
            documentID: record.id, versionID: document.currentVersionID,
            versionQueryID: document.versionQueryID, modified: record.modified ?? Date())
        }
      }
    }
  }

  /// The documents with a fresh archive, and their bytes, against all in the
  /// scope.
  public func libraryFileProgress(serverID: UUID, scope: LibraryFileScope = .library)
    async throws -> LibraryFileProgress
  {
    try await wrappingAsync("libraryFileProgress") {
      try await writer.read { db in
        try Self.libraryFileProgress(serverID: serverID, scope: scope, db)
      }
    }
  }

  /// Live ``libraryFileProgress(serverID:scope:)`` for the Offline & Sync screen.
  public func observeLibraryFileProgress(serverID: UUID, scope: LibraryFileScope = .library)
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

  /// The scope's restriction on `document d`; the library has none.
  private static func scopeClause(_ scope: LibraryFileScope) -> String {
    switch scope {
    case .library: ""
    case .keptOffline: "AND \(keptOfflineExists)"
    }
  }

  private static func documentsNeedingArchive(
    serverID: UUID, scope: LibraryFileScope, limit: Int, _ db: GRDB.Database
  ) throws -> [DocumentRecord] {
    try DocumentRecord.fetchAll(
      db,
      sql: """
        SELECT d.* FROM document d
        WHERE d.server_id = ?
          AND d.modified IS NOT NULL
          AND NOT \(freshArchiveExists)
          \(scopeClause(scope))
        ORDER BY d.id DESC
        LIMIT ?
        """,
      arguments: [serverID, limit])
  }

  /// The archive join shared by both progress queries, on a `document d`.
  private static let freshArchiveJoin = """
    LEFT JOIN file f
      ON f.server_id = d.server_id
      AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)
      AND f.kind = 'archive'
      AND f.modified IS d.modified
      AND d.modified IS NOT NULL
    """

  private static func libraryFileProgress(
    serverID: UUID, scope: LibraryFileScope, _ db: GRDB.Database
  ) throws -> LibraryFileProgress {
    // The kept scope starts from the membership so a member without a row
    // counts as missing; the library from the rows that can be validated.
    let sql =
      switch scope {
      case .library:
        """
        SELECT COUNT(*) AS total,
          COUNT(f.version_id) AS downloaded,
          COALESCE(SUM(f.size), 0) AS bytes
        FROM document d
        \(freshArchiveJoin)
        WHERE d.server_id = ? AND d.modified IS NOT NULL
        """
      case .keptOffline:
        """
        SELECT COUNT(*) AS total,
          COUNT(f.version_id) AS downloaded,
          COALESCE(SUM(f.size), 0) AS bytes
        FROM kept_offline k
        LEFT JOIN document d ON d.server_id = k.server_id AND d.id = k.document_id
        \(freshArchiveJoin)
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
