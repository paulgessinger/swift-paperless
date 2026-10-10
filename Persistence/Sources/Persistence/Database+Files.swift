import Common
import Foundation
import GRDB

/// A file found on disk without a row, to be entered into the index by the
/// repair walk. Carries what the legacy sidecar and the file system know.
public struct FileAdoption: Sendable, Equatable {
  public let key: ContentStore.Key
  public let size: Int64
  public let modified: Date?
  public let storedAt: Date
  public let lastAccessedAt: Date?

  public init(
    key: ContentStore.Key, size: Int64, modified: Date?, storedAt: Date, lastAccessedAt: Date?
  ) {
    self.key = key
    self.size = size
    self.modified = modified
    self.storedAt = storedAt
    self.lastAccessedAt = lastAccessedAt
  }
}

/// What the indexed files occupy, summed from `size`. Documents are the
/// originals and archives; thumbnails are kept apart because they are not
/// budgeted.
public struct FileUsage: Sendable, Equatable {
  public var documents: DiskUsage
  public var documentsByServer: [UUID: DiskUsage]
  public var thumbnails: DiskUsage

  public init(
    documents: DiskUsage = .zero, documentsByServer: [UUID: DiskUsage] = [:],
    thumbnails: DiskUsage = .zero
  ) {
    self.documents = documents
    self.documentsByServer = documentsByServer
    self.thumbnails = thumbnails
  }
}

/// The file index (`file`): the rows behind the `ContentStore`'s blobs.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// The row for `key` if its file was fetched against exactly `modified`.
  public func freshFile(_ key: ContentStore.Key, modified: Date) async throws -> FileRecord? {
    try await wrappingAsync("freshFile") {
      try await writer.read { db in
        try Self.file(for: key)
          .filter(Column("modified") == modified.timeIntervalSinceReferenceDate)
          .fetchOne(db)
      }
    }
  }

  /// Insert or replace the row for `key`. Returns the bytes the evictable
  /// files take after the write, for the caller to hold against the budget.
  @discardableResult
  public func recordFile(
    _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
    storedAt: Date, lastAccessedAt: Date?
  ) async throws -> Int64 {
    try await wrappingAsync("recordFile") {
      try await writer.write { db in
        try FileRecord(
          key, documentID: documentID, size: size, modified: modified, checksum: checksum,
          storedAt: storedAt, lastAccessedAt: lastAccessedAt
        ).save(db)
        return try Self.evictableBytes(db)
      }
    }
  }

  /// Stamp `key` as accessed at `date`.
  public func touchFile(_ key: ContentStore.Key, at date: Date) async throws {
    try await wrappingAsync("touchFile") {
      try await writer.write { db in
        _ = try Self.file(for: key).updateAll(
          db, Column("last_accessed_at").set(to: date.timeIntervalSinceReferenceDate))
      }
    }
  }

  public func deleteFile(_ key: ContentStore.Key) async throws {
    try await wrappingAsync("deleteFile") {
      try await writer.write { db in
        _ = try Self.file(for: key).deleteAll(db)
      }
    }
  }

  /// Delete `rows` as they were read: a row re-written since, with a newer
  /// `stored_at`, describes a new file and is left alone.
  @discardableResult
  public func deleteFiles(_ rows: [FileRecord]) async throws -> Int {
    try await wrappingAsync("deleteFiles") {
      try await writer.write { db in
        var deleted = 0
        for row in rows {
          deleted += try Self.file(serverID: row.serverId, versionID: row.versionId, kind: row.kind)
            .filter(Column("stored_at") == row.storedAt)
            .deleteAll(db)
        }
        return deleted
      }
    }
  }

  /// Bytes the evictable files take.
  public func evictableFileBytes() async throws -> Int64 {
    try await wrappingAsync("evictableFileBytes") {
      try await writer.read { db in try Self.evictableBytes(db) }
    }
  }

  /// Rows whose version no cached document is at any more: superseded
  /// versions, documents the cache dropped, and servers that are gone. The
  /// same rule as ``retainedContentVersions()``, applied in one query.
  public func unreferencedFiles() async throws -> [FileRecord] {
    try await wrappingAsync("unreferencedFiles") {
      try await writer.read { db in
        try FileRecord.fetchAll(
          db,
          sql: """
            SELECT f.* FROM file f
            WHERE NOT EXISTS (
              SELECT 1 FROM document d
              WHERE d.server_id = f.server_id
                AND COALESCE(NULLIF(d.current_version_id, 0), d.id) = f.version_id)
            """)
      }
    }
  }

  /// The evictable rows to remove, least recently accessed first, so that what
  /// remains fits `budget`. Never the most recently accessed row, so a single
  /// file larger than the budget stays; and never one accessed after
  /// `protectAccessedAfter`, which stops the walk since later rows are newer.
  public func evictionCandidates(budget: Int64, protectAccessedAfter cutoff: Date) async throws
    -> [FileRecord]
  {
    try await wrappingAsync("evictionCandidates") {
      try await writer.read { db in
        var total = try Self.evictableBytes(db)
        guard total > budget else { return [] }
        var rows = try FileRecord.evictable
          .order(Column("last_accessed_at").asc, Column("stored_at").asc)
          .fetchAll(db)
        rows.removeLast()
        var candidates: [FileRecord] = []
        for row in rows where total > budget {
          if let accessed = row.lastAccessedAt, accessed >= cutoff.timeIntervalSinceReferenceDate {
            break
          }
          candidates.append(row)
          total -= row.size
        }
        return candidates
      }
    }
  }

  /// Every key the index holds.
  public func allFileKeys() async throws -> Set<ContentStore.Key> {
    try await wrappingAsync("allFileKeys") {
      try await writer.read { db in
        Set(try FileRecord.fetchAll(db).compactMap(\.key))
      }
    }
  }

  /// Enter files found on disk into the index, resolving each one's document
  /// from the version it is filed under. Returns the keys of the files no
  /// cached document is at, which the caller removes.
  public func adoptFiles(_ candidates: [FileAdoption]) async throws -> [ContentStore.Key] {
    try await wrappingAsync("adoptFiles") {
      try await writer.write { db in
        var unresolved: [ContentStore.Key] = []
        for candidate in candidates {
          // The document whose current version the file is filed under; the
          // same rule as `retainedContentVersions`.
          let documentID = try UInt.fetchOne(
            db,
            sql: """
              SELECT id FROM document
              WHERE server_id = ? AND COALESCE(NULLIF(current_version_id, 0), id) = ?
              """,
            arguments: [candidate.key.serverID, candidate.key.versionID])
          guard let documentID else {
            unresolved.append(candidate.key)
            continue
          }
          try FileRecord(
            candidate.key, documentID: documentID, size: candidate.size,
            modified: candidate.modified, checksum: nil, storedAt: candidate.storedAt,
            lastAccessedAt: candidate.lastAccessedAt
          ).save(db)
        }
        return unresolved
      }
    }
  }

  /// What the indexed files occupy, from `size`; no directory walk.
  public func fileUsage() async throws -> FileUsage {
    try await wrappingAsync("fileUsage") {
      try await writer.read { db in
        var usage = FileUsage()
        for row in try Self.fileUsageByServerAndKind(db) {
          if row.kind == ContentStore.Kind.thumbnail.rawValue {
            usage.thumbnails += row.usage
          } else {
            usage.documents += row.usage
            usage.documentsByServer[row.serverID, default: .zero] += row.usage
          }
        }
        return usage
      }
    }
  }

  // MARK: - Query bodies

  static func file(serverID: UUID, versionID: UInt, kind: String)
    -> QueryInterfaceRequest<FileRecord>
  {
    FileRecord.filter(
      Column("server_id") == serverID && Column("version_id") == versionID
        && Column("kind") == kind)
  }

  private static func file(for key: ContentStore.Key) -> QueryInterfaceRequest<FileRecord> {
    file(serverID: key.serverID, versionID: key.versionID, kind: key.kind.rawValue)
  }

  static func evictableBytes(_ db: GRDB.Database) throws -> Int64 {
    try FileRecord.evictable
      .select(sum(Column("size")) ?? 0, as: Int64.self)
      .fetchOne(db) ?? 0
  }

  /// Count and bytes per server and kind, ordered by kind, for the usage sums
  /// and the statistics.
  static func fileUsageByServerAndKind(_ db: GRDB.Database) throws
    -> [(serverID: UUID, kind: String, usage: DiskUsage)]
  {
    let request =
      FileRecord
      .select(
        Column("server_id"), Column("kind"), count(Column("kind")).forKey("n"),
        (sum(Column("size")) ?? 0).forKey("bytes")
      )
      .group(Column("server_id"), Column("kind"))
      .order(Column("kind"))
    return try Row.fetchAll(db, request).map {
      (
        serverID: $0["server_id"], kind: $0["kind"],
        usage: DiskUsage(bytes: $0["bytes"], files: $0["n"])
      )
    }
  }
}

extension FileRecord {
  /// A row for `key`, with the dates as the table stores them.
  init(
    _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
    storedAt: Date, lastAccessedAt: Date?
  ) {
    self.init(
      serverId: key.serverID, versionId: key.versionID, kind: key.kind.rawValue,
      documentId: documentID, size: size, modified: modified?.timeIntervalSinceReferenceDate,
      checksum: checksum, storedAt: storedAt.timeIntervalSinceReferenceDate,
      lastAccessedAt: lastAccessedAt?.timeIntervalSinceReferenceDate)
  }
}
