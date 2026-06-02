import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("DocumentDetailCache")
struct DocumentDetailCacheTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  private func note(_ id: UInt, _ text: String, user: DocumentNote.User? = nil) -> DocumentNote {
    DocumentNote(id: id, note: text, created: date(1000), user: user)
  }

  private func metadata(_ checksum: String, archive: Bool = false) -> Metadata {
    Metadata(
      originalChecksum: checksum,
      originalSize: 1234,
      originalMimeType: "application/pdf",
      mediaFilename: "scan.pdf",
      hasArchiveVersion: archive,
      originalMetadata: [
        .init(namespace: "ns", prefix: "pre", key: "k", value: "v")
      ],
      archiveChecksum: archive ? "arch-\(checksum)" : nil,
      archiveMediaFilename: archive ? "archive.pdf" : nil,
      originalFilename: "scan.pdf",
      archiveSize: archive ? 5678 : nil,
      archiveMetadata: archive ? [.init(namespace: "a", prefix: "p", key: "ak", value: "av")] : nil,
      lang: "en")
  }

  // MARK: - Notes round-trip

  @Test("notes round-trip through set + read, preserving user")
  func notesRoundTrip() throws {
    let server = UUID()
    let database = try database(server)

    let notes = [
      note(1, "First", user: .init(id: 7, username: "alice")),
      note(2, "Second"),
    ]
    try database.setNotes(notes, serverID: server, documentID: 42)

    #expect(try database.notes(serverID: server, documentID: 42) == notes)
  }

  @Test("absent notes read as nil, distinct from a cached empty list")
  func notesAbsentVsEmpty() throws {
    let server = UUID()
    let database = try database(server)

    #expect(try database.notes(serverID: server, documentID: 42) == nil)

    try database.setNotes([], serverID: server, documentID: 42)
    #expect(try database.notes(serverID: server, documentID: 42) == [])
  }

  @Test("set replaces the whole notes list, never merges")
  func notesReplace() throws {
    let server = UUID()
    let database = try database(server)

    try database.setNotes([note(1, "a"), note(2, "b")], serverID: server, documentID: 42)
    try database.setNotes([note(3, "c")], serverID: server, documentID: 42)

    #expect(try database.notes(serverID: server, documentID: 42) == [note(3, "c")])
  }

  // MARK: - File-metadata round-trip

  @Test("file-metadata round-trips, including the archive fields and item lists")
  func metadataRoundTrip() throws {
    let server = UUID()
    let database = try database(server)

    let input = metadata("abc123", archive: true)
    try database.setFileMetadata(input, serverID: server, versionID: 9)

    let output = try #require(try database.fileMetadata(serverID: server, versionID: 9))
    #expect(output.originalChecksum == input.originalChecksum)
    #expect(output.hasArchiveVersion == input.hasArchiveVersion)
    #expect(output.archiveChecksum == input.archiveChecksum)
    #expect(output.archiveSize == input.archiveSize)
    #expect(output.originalMetadata.map(\.value) == ["v"])
    #expect(output.archiveMetadata?.map(\.value) == ["av"])
    #expect(output.lang == input.lang)
  }

  @Test("absent file-metadata reads as nil")
  func metadataAbsent() throws {
    let server = UUID()
    let database = try database(server)
    #expect(try database.fileMetadata(serverID: server, versionID: 9) == nil)
  }

  @Test("file-metadata is keyed per version")
  func metadataVersionKeyed() throws {
    let server = UUID()
    let database = try database(server)

    try database.setFileMetadata(metadata("v1sum"), serverID: server, versionID: 1)
    try database.setFileMetadata(metadata("v2sum"), serverID: server, versionID: 2)

    #expect(try database.fileMetadata(serverID: server, versionID: 1)?.originalChecksum == "v1sum")
    #expect(try database.fileMetadata(serverID: server, versionID: 2)?.originalChecksum == "v2sum")
  }

  // MARK: - Server isolation

  @Test("notes and file-metadata are isolated per server")
  func serverIsolation() throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    // Register the second server so its FK is satisfiable.
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    try database.setNotes([note(1, "a-note")], serverID: serverA, documentID: 42)
    try database.setFileMetadata(metadata("a-sum"), serverID: serverA, versionID: 9)

    #expect(try database.notes(serverID: serverB, documentID: 42) == nil)
    #expect(try database.fileMetadata(serverID: serverB, versionID: 9) == nil)
    #expect(try database.notes(serverID: serverA, documentID: 42) == [note(1, "a-note")])
  }

  // MARK: - Cascade

  @Test("clearCache drops cached notes and file-metadata")
  func clearCacheSweeps() throws {
    let server = UUID()
    let database = try database(server)

    try database.setNotes([note(1, "a")], serverID: server, documentID: 42)
    try database.setFileMetadata(metadata("sum"), serverID: server, versionID: 9)

    try database.clearCache()

    #expect(try database.notes(serverID: server, documentID: 42) == nil)
    #expect(try database.fileMetadata(serverID: server, versionID: 9) == nil)
  }
}
