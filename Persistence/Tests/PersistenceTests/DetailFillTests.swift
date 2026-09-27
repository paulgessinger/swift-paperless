import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// Covers the proactive notes/file-metadata detail-fill support queries: the
/// zero-note seed, the "needs a network fetch" sets, and the R3δ notes
/// invalidation.
@Suite("DetailFill")
struct DetailFillTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  private func doc(
    _ id: UInt, notesCount: Int = 0, modified: Date? = nil, versions: [DocumentVersion] = []
  ) -> Document {
    Document(
      id: id, title: "Doc \(id)", created: date(1000), tags: [], modified: modified,
      owner: .user(1), notes: NotesPayload(count: notesCount), versions: versions)
  }

  private func metadata(_ checksum: String) -> Metadata {
    Metadata(
      originalChecksum: checksum,
      originalSize: 1234,
      originalMimeType: "application/pdf",
      mediaFilename: "scan.pdf",
      hasArchiveVersion: false,
      originalMetadata: [],
      originalFilename: "scan.pdf",
      lang: "en")
  }

  // MARK: - Zero-note seed

  @Test("seed writes an empty notes row only for zero-note docs without one")
  func seedZeroNoteDocs() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [
        doc(1, notesCount: 0),  // seeded
        doc(2, notesCount: 0),  // already has a row → skipped
        doc(3, notesCount: 2),  // has notes → not seeded
      ], serverID: server)
    // Doc 2 already cached (non-empty here, could be anything) — must not be touched.
    try await database.setNotes(
      [.init(id: 9, note: "x", created: date(1))], serverID: server, documentID: 2)

    let seeded = try await database.seedEmptyNotesForZeroCountDocuments(serverID: server)
    #expect(seeded == 1)

    #expect(try await database.notes(serverID: server, documentID: 1) == [])
    // Doc 2's existing row is untouched (still one note), not overwritten with [].
    #expect(try await database.notes(serverID: server, documentID: 2)?.count == 1)
    // Doc 3 (has notes) is left for the network fetch — no row yet.
    #expect(try await database.notes(serverID: server, documentID: 3) == nil)
  }

  @Test("seed is idempotent — a second pass seeds nothing")
  func seedIdempotent() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [doc(1, notesCount: 0), doc(2, notesCount: 0)], serverID: server)

    #expect(try await database.seedEmptyNotesForZeroCountDocuments(serverID: server) == 2)
    #expect(try await database.seedEmptyNotesForZeroCountDocuments(serverID: server) == 0)
  }

  // MARK: - Needs-fetch sets

  @Test("documentIDsNeedingNotesFetch = notesCount>0 docs without a cached row")
  func needsNotesFetch() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [
        doc(1, notesCount: 0),  // no notes → free seed, never fetched
        doc(2, notesCount: 3),  // needs fetch
        doc(3, notesCount: 1),  // already cached → excluded
      ], serverID: server)
    try await database.setNotes(
      [.init(id: 9, note: "x", created: date(1))], serverID: server, documentID: 3)

    #expect(try await database.documentIDsNeedingNotesFetch(serverID: server) == [2])

    // Seeding zero-note docs does not add them to the fetch set.
    try await database.seedEmptyNotesForZeroCountDocuments(serverID: server)
    #expect(try await database.documentIDsNeedingNotesFetch(serverID: server) == [2])
  }

  @Test("documentIDsNeedingFileMetadataFetch keys on the current version, not any version")
  func missingFileMetadata() async throws {
    let server = UUID()
    let database = try database(server)
    let multiVersion = doc(
      1,
      versions: [
        DocumentVersion(id: 1, added: date(1000), isRoot: true),
        DocumentVersion(id: 9, added: date(5000), isRoot: false),  // current
      ])
    try await database.upsertDocuments([multiVersion, doc(2)], serverID: server)

    // Nothing cached → both missing.
    #expect(
      try await Set(database.documentIDsNeedingFileMetadataFetch(serverID: server)) == [1, 2])

    // Caching an *old* version (1) does not satisfy doc 1 — current is 9.
    try await database.setFileMetadata(
      metadata("old"), serverID: server, versionID: 1, documentModified: nil)
    #expect(
      try await Set(database.documentIDsNeedingFileMetadataFetch(serverID: server)) == [1, 2])

    // Caching the current version (9) clears doc 1. Doc 2's current version is
    // its own id (no versions) → cache under id 2.
    try await database.setFileMetadata(
      metadata("current"), serverID: server, versionID: 9, documentModified: nil)
    try await database.setFileMetadata(
      metadata("doc2"), serverID: server, versionID: 2, documentModified: nil)
    #expect(try await database.documentIDsNeedingFileMetadataFetch(serverID: server).isEmpty)
  }

  @Test(
    "file metadata fetched under another document modified is needed again",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/764", id: 764))
  func fileMetadataFollowsDocumentModified() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [doc(1, modified: date(100)), doc(2, modified: date(100)), doc(3, modified: date(100))],
      serverID: server)
    try await database.setFileMetadata(
      metadata("1"), serverID: server, versionID: 1, documentModified: date(100))
    try await database.setFileMetadata(
      metadata("2"), serverID: server, versionID: 2, documentModified: date(100))
    // Fetched without a cached document, so under an unknown date.
    try await database.setFileMetadata(
      metadata("3"), serverID: server, versionID: 3, documentModified: nil)
    #expect(try await database.documentIDsNeedingFileMetadataFetch(serverID: server) == [3])

    // A move (e.g. a storage path change) bumps `modified` without a new version.
    try await database.upsertDocuments([doc(2, modified: date(200))], serverID: server)
    #expect(try await database.documentIDsNeedingFileMetadataFetch(serverID: server) == [2, 3])

    try await database.setFileMetadata(
      metadata("2"), serverID: server, versionID: 2, documentModified: date(200))
    #expect(try await database.documentIDsNeedingFileMetadataFetch(serverID: server) == [3])
  }

  // MARK: - Notes from document responses

  private func note(_ id: UInt, _ text: String) -> DocumentNote {
    DocumentNote(id: id, note: text, created: date(1))
  }

  private func listing(_ id: UInt, _ notes: [DocumentNote]) -> Document {
    var document = doc(id)
    document.notes = NotesPayload(notes: notes)
    return document
  }

  private func denyNotes(_ database: Persistence.Database, _ server: UUID) async throws {
    let permissions = UserPermissions.empty(with: { $0.set(.view, to: true, for: .document) })
    try await database.setUISettings(
      UISettings(
        user: User(id: 1, isSuperUser: false, username: "alice", groups: []),
        permissions: permissions),
      serverID: server)
  }

  @Test("a document write caches the notes its response carried")
  func documentWriteCachesListedNotes() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.setNotes([note(9, "kept")], serverID: server, documentID: 2)

    // Document 2's response carried only a count, so its row stays.
    try await database.upsertDocuments(
      [listing(1, [note(1, "a")]), doc(2, notesCount: 1)], serverID: server)

    #expect(try await database.notes(serverID: server, documentID: 1) == [note(1, "a")])
    #expect(try await database.notes(serverID: server, documentID: 2) == [note(9, "kept")])
    #expect(try await database.documentIDsNeedingNotesFetch(serverID: server).isEmpty)
  }

  @Test("the delta replaces listed notes and drops the rest")
  func deltaReplacesListedNotes() async throws {
    let server = UUID()
    let database = try database(server)
    for id in [UInt(1), 2] {
      try await database.setNotes([note(id, "old")], serverID: server, documentID: id)
    }

    try await database.applyChangedDocuments(
      [listing(1, [note(1, "new")]), doc(2, notesCount: 1)], serverID: server)

    #expect(try await database.notes(serverID: server, documentID: 1) == [note(1, "new")])
    #expect(try await database.notes(serverID: server, documentID: 2) == nil)
  }

  @Test("without the notes view permission, listed notes are not cached")
  func listedNotesNeedViewPermission() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.setNotes([note(2, "old")], serverID: server, documentID: 2)
    try await denyNotes(database, server)

    try await database.upsertDocuments([listing(1, [note(1, "a")])], serverID: server)
    #expect(try await database.notes(serverID: server, documentID: 1) == nil)

    // The delta still drops what was cached before.
    try await database.applyChangedDocuments([listing(2, [note(2, "new")])], serverID: server)
    #expect(try await database.notes(serverID: server, documentID: 2) == nil)
  }

  // MARK: - Invalidation

  @Test("invalidateNotes drops only the named docs' rows")
  func invalidate() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [doc(1, notesCount: 1), doc(2, notesCount: 1), doc(3, notesCount: 1)], serverID: server)
    for id in [UInt(1), 2, 3] {
      try await database.setNotes(
        [.init(id: id, note: "n", created: date(1))], serverID: server, documentID: id)
    }

    try await database.invalidateNotes(serverID: server, documentIDs: [1, 3])

    #expect(try await database.notes(serverID: server, documentID: 1) == nil)
    #expect(try await database.notes(serverID: server, documentID: 2)?.count == 1)
    #expect(try await database.notes(serverID: server, documentID: 3) == nil)
    // The invalidated docs (which have notes) resurface in the fetch set.
    #expect(try await Set(database.documentIDsNeedingNotesFetch(serverID: server)) == [1, 3])
  }

  // MARK: - Server scoping

  @Test("all detail-fill queries are scoped to one server")
  func serverScoping() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    try await database.upsertDocuments(
      [doc(1, notesCount: 0), doc(2, notesCount: 2)], serverID: serverA)
    try await database.upsertDocuments(
      [doc(1, notesCount: 0), doc(2, notesCount: 2)], serverID: serverB)

    // Seeding A must not touch B.
    #expect(try await database.seedEmptyNotesForZeroCountDocuments(serverID: serverA) == 1)
    #expect(try await database.notes(serverID: serverB, documentID: 1) == nil)

    #expect(try await database.documentIDsNeedingNotesFetch(serverID: serverA) == [2])
    #expect(try await database.documentIDsNeedingNotesFetch(serverID: serverB) == [2])

    try await database.setNotes([], serverID: serverA, documentID: 2)
    try await database.invalidateNotes(serverID: serverA, documentIDs: [2])
    // B's doc 2 is untouched.
    #expect(try await database.documentIDsNeedingNotesFetch(serverID: serverB) == [2])
  }
  @Test("excluding drops known-bad ids from both detail-fill queries")
  func excludingSkipsFailedIDs() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments(
      [doc(1, notesCount: 1), doc(2, notesCount: 1), doc(3, notesCount: 1)], serverID: server)

    #expect(try await database.documentIDsNeedingNotesFetch(serverID: server) == [1, 2, 3])
    #expect(
      try await database.documentIDsNeedingNotesFetch(serverID: server, excluding: [2]) == [1, 3])
    #expect(
      try await database.documentIDsNeedingFileMetadataFetch(serverID: server, excluding: [1, 3])
        == [2])
  }

  @Test("detail-fill queries return ids in a stable order")
  func detailQueriesAreOrdered() async throws {
    let server = UUID()
    let database = try database(server)

    // Inserted out of order: the caller resumes by taking what is still
    // missing, which only works if the order doesn't wander between passes.
    try await database.upsertDocuments(
      [doc(30, notesCount: 1), doc(10, notesCount: 1), doc(20, notesCount: 1)], serverID: server)

    #expect(try await database.documentIDsNeedingNotesFetch(serverID: server) == [10, 20, 30])
    #expect(
      try await database.documentIDsNeedingFileMetadataFetch(serverID: server) == [10, 20, 30])
  }

}
