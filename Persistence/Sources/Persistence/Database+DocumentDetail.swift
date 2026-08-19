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
  public func setNotes(_ notes: [DocumentNote], serverID: UUID, documentID: UInt)
    throws(DatabaseError)
  {
    try wrapping("setNotes") {
      try writer.write { db in
        try DocumentNoteRecord(serverId: serverID, documentId: documentID, notes: notes)
          .upsert(db)
      }
    }
  }

  /// A document's cached notes, or `nil` if never cached. `nil` (absent) is
  /// distinct from `[]` (cached, genuinely no notes) so the offline fallback can
  /// tell "nothing to serve" from "served an empty list".
  public func notes(serverID: UUID, documentID: UInt) throws(DatabaseError) -> [DocumentNote]? {
    try wrapping("notes") {
      try writer.read { db in
        try DocumentNoteRecord
          .filter(Column("server_id") == serverID && Column("document_id") == documentID)
          .fetchOne(db)?
          .domain
      }
    }
  }

  // MARK: - File-metadata (immutable, version-keyed)

  /// Cache a file version's `/metadata/`. Immutable per version, so this only
  /// writes the first time a version is seen (re-writing an identical row is
  /// harmless).
  public func setFileMetadata(_ metadata: Metadata, serverID: UUID, versionID: UInt)
    throws(DatabaseError)
  {
    try wrapping("setFileMetadata") {
      try writer.write { db in
        try FileMetadataRecord(serverId: serverID, versionId: versionID, domain: metadata)
          .upsert(db)
      }
    }
  }

  /// A file version's cached metadata, or `nil` if never cached.
  public func fileMetadata(serverID: UUID, versionID: UInt) throws(DatabaseError) -> Metadata? {
    try wrapping("fileMetadata") {
      try writer.read { db in
        try FileMetadataRecord
          .filter(Column("server_id") == serverID && Column("version_id") == versionID)
          .fetchOne(db)?
          .domain
      }
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
  ///
  /// One `INSERT … SELECT` rather than a full-table `fetchAll` and a decode per
  /// row: this runs inside the write transaction, so decoding every document's
  /// JSON blob to read one integer held the writer lock for time proportional
  /// to the library — with `busy_timeout` at 5s, long enough for the Share
  /// Extension to stall behind it. `'[]'` is exactly what an empty
  /// `DocumentNoteRecord.notes` encodes to.
  @discardableResult
  public func seedEmptyNotesForZeroCountDocuments(serverID: UUID) throws -> Int {
    try writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO document_note (server_id, document_id, data)
          SELECT d.server_id, d.id, '[]'
          FROM document d
          LEFT JOIN document_note n
            ON n.server_id = d.server_id AND n.document_id = d.id
          WHERE d.server_id = ?
            AND n.document_id IS NULL
            AND json_extract(d.data, '$.notesCount') = 0
          """,
        arguments: [serverID])
      return db.changesCount
    }
  }

  /// Cached document ids that have notes (`notesCount > 0`) but no cached notes
  /// row yet — the only documents that need an R4n `/notes/` request. Zero-note
  /// documents are covered for free by `seedEmptyNotesForZeroCountDocuments`.
  ///
  /// Expressed as SQL rather than a `fetchAll` + Swift filter: the caller runs
  /// this on every foreground over the whole `document` table, and decoding
  /// every row's JSON blob to read one integer is work proportional to the
  /// library on the main actor. `ORDER BY d.id` so the result is stable, which
  /// is what lets a caller take a prefix and have the next pass resume rather
  /// than re-walk the same head.
  ///
  /// - Parameter excluding: ids to leave out — the caller's per-session record
  ///   of documents whose fetch already failed, so one permanently failing
  ///   document can't sit at the head of the list forever.
  public func documentIDsNeedingNotesFetch(
    serverID: UUID, excluding: Set<UInt> = []
  ) throws -> [UInt] {
    try writer.read { db in
      try UInt.fetchAll(
        db,
        sql: """
          SELECT d.id FROM document d
          LEFT JOIN document_note n
            ON n.server_id = d.server_id AND n.document_id = d.id
          WHERE d.server_id = ?
            AND n.document_id IS NULL
            AND json_extract(d.data, '$.notesCount') > 0
          ORDER BY d.id
          """,
        arguments: [serverID]
      )
      .filter { !excluding.contains($0) }
    }
  }

  /// Cached document ids whose *current* file version has no cached
  /// `file_metadata` row — the documents that need an R4m `/metadata/` request.
  /// File-metadata is version-keyed and immutable, so a document already covered
  /// for its current version is never re-fetched. Mirrors the version-key
  /// resolution in `CachingRepository.metadata(documentId:)` (current version,
  /// falling back to the document id).
  ///
  /// Same shape as ``documentIDsNeedingNotesFetch(serverID:excluding:)`` and for
  /// the same reason. `currentVersionID` — the highest version id, falling back
  /// to the document id when a document has no versions (`DocumentModel`) — is
  /// reproduced here in SQL rather than by decoding each row.
  public func documentIDsMissingFileMetadata(
    serverID: UUID, excluding: Set<UInt> = []
  ) throws -> [UInt] {
    try writer.read { db in
      try UInt.fetchAll(
        db,
        sql: """
          SELECT d.id FROM document d
          WHERE d.server_id = ?
            AND NOT EXISTS (
              SELECT 1 FROM file_metadata f
              WHERE f.server_id = d.server_id
                AND f.version_id = COALESCE(
                  (SELECT MAX(CAST(json_extract(v.value, '$.id') AS INTEGER))
                   FROM json_each(d.data, '$.versions') v),
                  d.id)
            )
          ORDER BY d.id
          """,
        arguments: [serverID]
      )
      .filter { !excluding.contains($0) }
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
