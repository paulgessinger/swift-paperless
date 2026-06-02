import DataModel
import Foundation
import GRDB

/// Per-document detail-cache operations (notes + file-metadata) — the entry
/// points AppShared uses to read or write the two Tier-2 sub-resources; GRDB
/// stays sealed inside `Persistence`.
///
/// Both follow the same network-first → write-through → offline-fallback shape
/// as `document(id:)`: the caching repository forwards to the server, replaces
/// the cached row on success, and serves the cached row on failure. Notes are
/// document-keyed and mutable; file-metadata is version-keyed and immutable.
extension Database {
  // MARK: - Notes (mutable, document-keyed)

  /// Replace a document's cached notes list (a row replace, not a per-note
  /// merge — the endpoint and mutations always return the full list).
  public func setNotes(_ notes: [DocumentNote], serverID: UUID, documentID: UInt) throws {
    try writer.write { db in
      try DocumentNoteRecord(serverId: serverID, documentId: documentID, notes: notes)
        .upsert(db)
    }
  }

  /// A document's cached notes, or `nil` if never cached. `nil` (absent) is
  /// distinct from `[]` (cached, genuinely no notes) so the offline fallback can
  /// tell "nothing to serve" from "served an empty list".
  public func notes(serverID: UUID, documentID: UInt) throws -> [DocumentNote]? {
    try writer.read { db in
      try DocumentNoteRecord
        .filter(Column("server_id") == serverID && Column("document_id") == documentID)
        .fetchOne(db)?
        .domain
    }
  }

  // MARK: - File-metadata (immutable, version-keyed)

  /// Cache a file version's `/metadata/`. Immutable per version, so this only
  /// writes the first time a version is seen (re-writing an identical row is
  /// harmless).
  public func setFileMetadata(_ metadata: Metadata, serverID: UUID, versionID: UInt) throws {
    try writer.write { db in
      try FileMetadataRecord(serverId: serverID, versionId: versionID, domain: metadata)
        .upsert(db)
    }
  }

  /// A file version's cached metadata, or `nil` if never cached.
  public func fileMetadata(serverID: UUID, versionID: UInt) throws -> Metadata? {
    try writer.read { db in
      try FileMetadataRecord
        .filter(Column("server_id") == serverID && Column("version_id") == versionID)
        .fetchOne(db)?
        .domain
    }
  }
}
