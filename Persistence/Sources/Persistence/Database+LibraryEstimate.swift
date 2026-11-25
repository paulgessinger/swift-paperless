import DataModel
import Foundation
import GRDB

/// What the device knows about the sizes of a server's files, for estimating
/// what its whole library would take (``LibrarySizeEstimate``).
public struct LibrarySizeSample: Sendable, Equatable {
  /// The server's cached documents.
  public var documents: Int
  /// The documents whose file size is known, and their sum.
  public var files: LibrarySizeEstimate.Known
  public var thumbnails: LibrarySizeEstimate.Known
  public var texts: LibrarySizeEstimate.Known
  /// The server's documents in the full-text index. What they take there is
  /// not known per server; see ``Database/searchIndexUsage()``.
  public var indexedDocuments: Int
}

/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// The sizes known for `serverID`'s files, from the file index and the
  /// cached file metadata. No request.
  ///
  /// A document's file size is its downloaded archive's where there is one,
  /// and otherwise the size its file metadata reports for what a download
  /// would fetch: the archived version, or the original where the document
  /// has none.
  public func librarySizeSample(serverID: UUID) async throws -> LibrarySizeSample {
    try await wrappingAsync("librarySizeSample") {
      try await writer.read { db in
        let sized = try Row.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes
            FROM (\(Self.documentFileSizeSQL)) WHERE size IS NOT NULL
            """,
          arguments: [serverID])
        func known(kind: String) throws -> LibrarySizeEstimate.Known {
          let row = try Row.fetchOne(
            db,
            sql: """
              SELECT COUNT(*) AS n, COALESCE(SUM(size), 0) AS bytes FROM file
              WHERE server_id = ? AND kind = ?
              """,
            arguments: [serverID, kind])
          return .init(documents: row?["n"] ?? 0, bytes: row?["bytes"] ?? 0)
        }
        return LibrarySizeSample(
          documents: try DocumentRecord.filter(Column("server_id") == serverID).fetchCount(db),
          files: .init(documents: sized?["n"] ?? 0, bytes: sized?["bytes"] ?? 0),
          thumbnails: try known(kind: "thumbnail"),
          texts: try known(kind: "content"),
          indexedDocuments: try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM content_index WHERE server_id = ?",
            arguments: [serverID]) ?? 0)
      }
    }
  }

  /// Up to `limit` of `serverID`'s documents whose file size isn't known,
  /// picked at random so that fetching their file metadata gives an unbiased
  /// sample: the documents a user happens to have opened need not be typical.
  public func documentIDsWithoutKnownFileSize(
    serverID: UUID, limit: Int
  ) async throws -> [UInt] {
    try await wrappingAsync("documentIDsWithoutKnownFileSize") {
      try await writer.read { db in
        try UInt.fetchAll(
          db,
          sql: """
            SELECT id FROM (\(Self.documentFileSizeSQL)) WHERE size IS NULL
            ORDER BY RANDOM() LIMIT ?
            """,
          arguments: [serverID, limit])
      }
    }
  }

  /// The full-text index's size and how many documents it holds, every
  /// server's.
  public func searchIndexUsage() async throws -> LibrarySizeEstimate.Known {
    let bytes = try await searchIndexBytes()
    return try await wrappingAsync("searchIndexUsage") {
      try await writer.read { db in
        .init(
          documents: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM content_index") ?? 0,
          bytes: bytes)
      }
    }
  }

  /// Each of a server's documents with the size of its file, `NULL` where
  /// unknown. One argument: the server.
  private static let documentFileSizeSQL = """
    SELECT d.id, COALESCE(
      (SELECT f.size FROM file f
        WHERE f.server_id = d.server_id AND f.kind = 'archive'
          AND f.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id)),
      (SELECT COALESCE(json_extract(m.data, '$.archiveSize'),
                       json_extract(m.data, '$.originalSize'))
        FROM file_metadata m
        WHERE m.server_id = d.server_id
          AND m.version_id = COALESCE(NULLIF(d.current_version_id, 0), d.id))
    ) AS size
    FROM document d WHERE d.server_id = ?
    """
}
