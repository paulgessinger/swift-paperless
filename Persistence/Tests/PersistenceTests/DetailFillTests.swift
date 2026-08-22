import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// Covers the proactive notes/file-metadata detail-fill support queries
/// (Stage 9): the zero-note seed, the "needs a network fetch" sets, and the
/// R3δ notes invalidation.
@Suite("DetailFill")
struct DetailFillTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  private func doc(
    _ id: UInt, notesCount: Int = 0, versions: [DocumentVersion] = []
  ) -> Document {
    Document(
      id: id, title: "Doc \(id)", created: date(1000), tags: [],
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
  func seedZeroNoteDocs() throws {
    let server = UUID()
    let database = try database(server)
    try database.upsertDocuments(
      [
        doc(1, notesCount: 0),  // seeded
        doc(2, notesCount: 0),  // already has a row → skipped
        doc(3, notesCount: 2),  // has notes → not seeded
      ], serverID: server)
    // Doc 2 already cached (non-empty here, could be anything) — must not be touched.
    try database.setNotes(
      [.init(id: 9, note: "x", created: date(1))], serverID: server, documentID: 2)

    let seeded = try database.seedEmptyNotesForZeroCountDocuments(serverID: server)
    #expect(seeded == 1)

    #expect(try database.notes(serverID: server, documentID: 1) == [])
    // Doc 2's existing row is untouched (still one note), not overwritten with [].
    #expect(try database.notes(serverID: server, documentID: 2)?.count == 1)
    // Doc 3 (has notes) is left for the network fetch — no row yet.
    #expect(try database.notes(serverID: server, documentID: 3) == nil)
  }

  @Test("seed is idempotent — a second pass seeds nothing")
  func seedIdempotent() throws {
    let server = UUID()
    let database = try database(server)
    try database.upsertDocuments([doc(1, notesCount: 0), doc(2, notesCount: 0)], serverID: server)

    #expect(try database.seedEmptyNotesForZeroCountDocuments(serverID: server) == 2)
    #expect(try database.seedEmptyNotesForZeroCountDocuments(serverID: server) == 0)
  }

  // MARK: - Needs-fetch sets

  @Test("documentIDsNeedingNotesFetch = notesCount>0 docs without a cached row")
  func needsNotesFetch() throws {
    let server = UUID()
    let database = try database(server)
    try database.upsertDocuments(
      [
        doc(1, notesCount: 0),  // no notes → free seed, never fetched
        doc(2, notesCount: 3),  // needs fetch
        doc(3, notesCount: 1),  // already cached → excluded
      ], serverID: server)
    try database.setNotes(
      [.init(id: 9, note: "x", created: date(1))], serverID: server, documentID: 3)

    #expect(try database.documentIDsNeedingNotesFetch(serverID: server) == [2])

    // Seeding zero-note docs does not add them to the fetch set.
    try database.seedEmptyNotesForZeroCountDocuments(serverID: server)
    #expect(try database.documentIDsNeedingNotesFetch(serverID: server) == [2])
  }

  @Test("documentIDsMissingFileMetadata keys on the current version, not any version")
  func missingFileMetadata() throws {
    let server = UUID()
    let database = try database(server)
    let multiVersion = doc(
      1,
      versions: [
        DocumentVersion(id: 1, added: date(1000), isRoot: true),
        DocumentVersion(id: 9, added: date(5000), isRoot: false),  // current
      ])
    try database.upsertDocuments([multiVersion, doc(2)], serverID: server)

    // Nothing cached → both missing.
    #expect(try Set(database.documentIDsMissingFileMetadata(serverID: server)) == [1, 2])

    // Caching an *old* version (1) does not satisfy doc 1 — current is 9.
    try database.setFileMetadata(metadata("old"), serverID: server, versionID: 1)
    #expect(try Set(database.documentIDsMissingFileMetadata(serverID: server)) == [1, 2])

    // Caching the current version (9) clears doc 1. Doc 2's current version is
    // its own id (no versions) → cache under id 2.
    try database.setFileMetadata(metadata("current"), serverID: server, versionID: 9)
    try database.setFileMetadata(metadata("doc2"), serverID: server, versionID: 2)
    #expect(try database.documentIDsMissingFileMetadata(serverID: server).isEmpty)
  }

  // MARK: - Invalidation

  @Test("invalidateNotes drops only the named docs' rows")
  func invalidate() throws {
    let server = UUID()
    let database = try database(server)
    try database.upsertDocuments(
      [doc(1, notesCount: 1), doc(2, notesCount: 1), doc(3, notesCount: 1)], serverID: server)
    for id in [UInt(1), 2, 3] {
      try database.setNotes(
        [.init(id: id, note: "n", created: date(1))], serverID: server, documentID: id)
    }

    try database.invalidateNotes(serverID: server, documentIDs: [1, 3])

    #expect(try database.notes(serverID: server, documentID: 1) == nil)
    #expect(try database.notes(serverID: server, documentID: 2)?.count == 1)
    #expect(try database.notes(serverID: server, documentID: 3) == nil)
    // The invalidated docs (which have notes) resurface in the fetch set.
    #expect(try Set(database.documentIDsNeedingNotesFetch(serverID: server)) == [1, 3])
  }

  // MARK: - Server scoping

  @Test("all detail-fill queries are scoped to one server")
  func serverScoping() throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    try database.upsertDocuments([doc(1, notesCount: 0), doc(2, notesCount: 2)], serverID: serverA)
    try database.upsertDocuments([doc(1, notesCount: 0), doc(2, notesCount: 2)], serverID: serverB)

    // Seeding A must not touch B.
    #expect(try database.seedEmptyNotesForZeroCountDocuments(serverID: serverA) == 1)
    #expect(try database.notes(serverID: serverB, documentID: 1) == nil)

    #expect(try database.documentIDsNeedingNotesFetch(serverID: serverA) == [2])
    #expect(try database.documentIDsNeedingNotesFetch(serverID: serverB) == [2])

    try database.setNotes([], serverID: serverA, documentID: 2)
    try database.invalidateNotes(serverID: serverA, documentIDs: [2])
    // B's doc 2 is untouched.
    #expect(try database.documentIDsNeedingNotesFetch(serverID: serverB) == [2])
  }
  @Test("excluding drops known-bad ids from both detail-fill queries")
  func excludingSkipsFailedIDs() throws {
    let server = UUID()
    let database = try database(server)

    try database.upsertDocuments(
      [doc(1, notesCount: 1), doc(2, notesCount: 1), doc(3, notesCount: 1)], serverID: server)

    #expect(try database.documentIDsNeedingNotesFetch(serverID: server) == [1, 2, 3])
    #expect(
      try database.documentIDsNeedingNotesFetch(serverID: server, excluding: [2]) == [1, 3])
    #expect(
      try database.documentIDsMissingFileMetadata(serverID: server, excluding: [1, 3]) == [2])
  }

  @Test("detail-fill queries return ids in a stable order")
  func detailQueriesAreOrdered() throws {
    let server = UUID()
    let database = try database(server)

    // Inserted out of order: the caller resumes by taking what is still
    // missing, which only works if the order doesn't wander between passes.
    try database.upsertDocuments(
      [doc(30, notesCount: 1), doc(10, notesCount: 1), doc(20, notesCount: 1)], serverID: server)

    #expect(try database.documentIDsNeedingNotesFetch(serverID: server) == [10, 20, 30])
    #expect(try database.documentIDsMissingFileMetadata(serverID: server) == [10, 20, 30])
  }

}
