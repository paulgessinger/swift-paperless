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

  // MARK: - Proactive detail fill (Stage 9)

  /// Seed an empty `document_note` row for every cached document that reports
  /// zero notes and has no cached notes row yet — no network. The list/fill
  /// payload carries the notes *count* for free (`DocumentRecord.Payload
  /// .notesCount`), so a zero-note document can be marked "seeded" (renderable
  /// offline as "no notes") without a `/notes/` request. Returns the number of
  /// rows seeded. Only documents that actually have notes need a network fetch
  /// (`documentIDsNeedingNotesFetch`).
  @discardableResult
  public func seedEmptyNotesForZeroCountDocuments(serverID: UUID) throws -> Int {
    try writer.write { db in
      let cachedNoteIDs =
        try DocumentNoteRecord
        .select(Column("document_id"), as: UInt.self)
        .filter(Column("server_id") == serverID)
        .fetchSet(db)
      let zeroNoteDocs =
        try DocumentRecord
        .filter(Column("server_id") == serverID)
        .fetchAll(db)
        .filter { $0.payload.notesCount == 0 && !cachedNoteIDs.contains($0.id) }
      for record in zeroNoteDocs {
        try DocumentNoteRecord(serverId: serverID, documentId: record.id, notes: [DocumentNote]())
          .upsert(db)
      }
      return zeroNoteDocs.count
    }
  }

  /// Cached document ids that have notes (`notesCount > 0`) but no cached notes
  /// row yet — the only documents that need an R4n `/notes/` request. Zero-note
  /// documents are covered for free by `seedEmptyNotesForZeroCountDocuments`.
  public func documentIDsNeedingNotesFetch(serverID: UUID) throws -> [UInt] {
    try writer.read { db in
      let cachedNoteIDs =
        try DocumentNoteRecord
        .select(Column("document_id"), as: UInt.self)
        .filter(Column("server_id") == serverID)
        .fetchSet(db)
      return
        try DocumentRecord
        .filter(Column("server_id") == serverID)
        .fetchAll(db)
        .filter { $0.payload.notesCount > 0 && !cachedNoteIDs.contains($0.id) }
        .map(\.id)
    }
  }

  /// Cached document ids whose *current* file version has no cached
  /// `file_metadata` row — the documents that need an R4m `/metadata/` request.
  /// File-metadata is version-keyed and immutable, so a document already covered
  /// for its current version is never re-fetched. Mirrors the version-key
  /// resolution in `CachingRepository.metadata(documentId:)` (current version,
  /// falling back to the document id).
  public func documentIDsMissingFileMetadata(serverID: UUID) throws -> [UInt] {
    try writer.read { db in
      let cachedVersionIDs =
        try FileMetadataRecord
        .select(Column("version_id"), as: UInt.self)
        .filter(Column("server_id") == serverID)
        .fetchSet(db)
      return
        try DocumentRecord
        .filter(Column("server_id") == serverID)
        .fetchAll(db)
        .filter { !cachedVersionIDs.contains($0.domain.currentVersionID) }
        .map(\.id)
    }
  }

  /// Drop cached notes rows for the given documents (no network). The R3δ delta
  /// calls this for documents whose `modified` bumped (note edits bump it too),
  /// so the next detail fill re-seeds or re-fetches their notes against the
  /// fresh `notesCount`. Explicit bookkeeping, not an FK cascade.
  public func invalidateNotes(serverID: UUID, documentIDs: [UInt]) throws {
    guard !documentIDs.isEmpty else { return }
    try writer.write { db in
      _ =
        try DocumentNoteRecord
        .filter(Column("server_id") == serverID && documentIDs.contains(Column("document_id")))
        .deleteAll(db)
    }
  }
}
