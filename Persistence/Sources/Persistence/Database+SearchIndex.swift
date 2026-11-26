import Common
import Foundation
import GRDB

/// A stored document text the full-text index doesn't hold, or holds an
/// older copy of.
public struct ContentIndexCandidate: Sendable, Equatable {
  public let serverID: UUID
  public let documentID: UInt
  public let versionID: UInt
  /// The `file` row's, which ``Database/indexContent(_:)`` checks the row
  /// still has before it writes.
  public let storedAt: Double
  public let checksum: String?

  /// Where the `ContentStore` keeps the text.
  public var key: ContentStore.Key {
    ContentStore.Key(serverID: serverID, versionID: versionID, kind: .content)
  }
}

/// What the full-text index covers for one server.
public struct SearchIndexCoverage: Sendable, Equatable {
  /// Documents whose text is indexed.
  public var indexedDocuments: Int
  /// Stored texts not indexed yet.
  public var awaitingIndex: Int
  /// Cached documents, with or without a stored text.
  public var documents: Int

  public init(indexedDocuments: Int = 0, awaitingIndex: Int = 0, documents: Int = 0) {
    self.indexedDocuments = indexedDocuments
    self.awaitingIndex = awaitingIndex
    self.documents = documents
  }
}

/// The full-text index over the stored document texts (`content_index`,
/// `content_fts`; see `V22_CreateSearchIndex`).
///
/// The index is derived from the `content` files the `ContentStore` holds, and
/// the database can't read those. So the caller walks
/// ``contentAwaitingIndex(limit:)``, reads each text and hands it to
/// ``indexContent(_:)``. Removal needs no caller: the triggers drop an entry
/// with its `file` row.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// Stored texts the index doesn't hold as they are now, every server's,
  /// newest file first so a text stored a moment ago is searchable first.
  ///
  /// - Parameter storedBefore: only files stored before this (a candidate's
  ///   ``ContentIndexCandidate/storedAt``), for walking the backlog in pages
  ///   without meeting the same candidate twice. A text that can't be indexed
  ///   would otherwise head every page.
  public func contentAwaitingIndex(
    limit: Int, storedBefore: Double? = nil
  ) async throws -> [ContentIndexCandidate] {
    try await wrappingAsync("contentAwaitingIndex") {
      try await writer.read { db in
        try Row.fetchAll(
          db,
          sql: """
            SELECT f.server_id, f.document_id, f.version_id, f.stored_at, f.checksum
            FROM file f
            \(Self.awaitingIndexJoin)
              AND (?1 IS NULL OR f.stored_at < ?1)
            ORDER BY f.stored_at DESC
            LIMIT ?2
            """,
          arguments: [storedBefore, limit]
        ).map {
          ContentIndexCandidate(
            serverID: $0["server_id"], documentID: $0["document_id"],
            versionID: $0["version_id"], storedAt: $0["stored_at"], checksum: $0["checksum"])
        }
      }
    }
  }

  /// Index `texts`, each replacing what the index held for its document.
  ///
  /// A candidate whose `file` row has changed or gone since it was read is
  /// skipped: the text in hand may no longer be the stored one, and the next
  /// pass picks the document up again. Returns how many were written.
  @discardableResult
  public func indexContent(
    _ texts: [(candidate: ContentIndexCandidate, text: String)]
  ) async throws -> Int {
    guard !texts.isEmpty else { return 0 }
    return try await wrappingAsync("indexContent") {
      try await writer.write { db in
        let current = try db.cachedStatement(
          sql: """
            SELECT 1 FROM file
            WHERE server_id = ? AND version_id = ? AND kind = 'content' AND stored_at = ?
            """)
        let delete = try db.cachedStatement(
          sql: "DELETE FROM content_index WHERE server_id = ? AND document_id = ?")
        let insert = try db.cachedStatement(
          sql: """
            INSERT INTO content_index
              (server_id, document_id, version_id, checksum, stored_at, length)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        let insertText = try db.cachedStatement(
          sql: "INSERT INTO content_fts (rowid, content) VALUES (?, ?)")
        var written = 0
        for (candidate, text) in texts {
          let isCurrent = try Bool.fetchOne(
            current,
            arguments: [candidate.serverID, candidate.versionID, candidate.storedAt])
          guard isCurrent == true else { continue }
          // The trigger removes the old entry's text with its row.
          try delete.execute(arguments: [candidate.serverID, candidate.documentID])
          try insert.execute(arguments: [
            candidate.serverID, candidate.documentID, candidate.versionID, candidate.checksum,
            candidate.storedAt, text.count,
          ])
          try insertText.execute(arguments: [db.lastInsertedRowID, text])
          written += 1
        }
        return written
      }
    }
  }

  /// What the index covers for `serverID`.
  public func searchIndexCoverage(serverID: UUID) async throws -> SearchIndexCoverage {
    try await wrappingAsync("searchIndexCoverage") {
      try await writer.read { db in try Self.searchIndexCoverage(db, serverID: serverID) }
    }
  }

  static func searchIndexCoverage(
    _ db: GRDB.Database, serverID: UUID
  ) throws -> SearchIndexCoverage {
    SearchIndexCoverage(
      indexedDocuments: try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM content_index WHERE server_id = ?",
        arguments: [serverID]) ?? 0,
      awaitingIndex: try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM file f \(awaitingIndexJoin) AND f.server_id = ?",
        arguments: [serverID]) ?? 0,
      documents: try DocumentRecord.filter(Column("server_id") == serverID).fetchCount(db))
  }

  /// Live ``searchIndexCoverage(serverID:)``. Re-runs for every text indexed,
  /// so a consumer throttles it.
  public func observeSearchIndexCoverage(
    serverID: UUID
  ) -> AsyncThrowingStream<SearchIndexCoverage, Error> {
    let observation =
      ValueObservation
      .tracking { db in try Self.searchIndexCoverage(db, serverID: serverID) }
      .removeDuplicates()
    return stream(observation)
  }

  /// Bytes the full-text index takes inside the database file, every
  /// server's. Read from the index's own segments, so it is a little under
  /// what the pages holding them occupy. The file's size (``diskUsage()``)
  /// includes it.
  public func searchIndexBytes() async throws -> Int64 {
    try await wrappingAsync("searchIndexBytes") {
      try await writer.read { db in
        try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(LENGTH(block)), 0) FROM content_fts_data")
          ?? 0
      }
    }
  }

  /// Merge the index's segments. Worth it after a large fill: each
  /// ``indexContent(_:)`` batch adds a segment, and a search reads them all.
  public func optimizeSearchIndex() async throws {
    try await wrappingAsync("optimizeSearchIndex") {
      try await writer.write { db in
        try db.execute(sql: "INSERT INTO content_fts (content_fts) VALUES ('optimize')")
      }
    }
  }

  // MARK: - Query bodies

  /// `file f` narrowed to the texts the index doesn't hold as stored. A
  /// checksum decides where the file has one; an adopted file has none, and
  /// its `stored_at` decides instead.
  private static let awaitingIndexJoin = """
    LEFT JOIN content_index ci
      ON ci.server_id = f.server_id AND ci.document_id = f.document_id
    WHERE f.kind = 'content'
      AND (ci.id IS NULL
        OR ci.version_id IS NOT f.version_id
        OR (f.checksum IS NOT NULL AND ci.checksum IS NOT f.checksum)
        OR (f.checksum IS NULL AND ci.stored_at IS NOT f.stored_at))
    """
}
