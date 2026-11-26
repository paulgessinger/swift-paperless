import Common
import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Library size sample")
struct LibraryEstimateTests {
  private let server = UUID()

  private func database() throws -> Persistence.Database {
    try Database.seeded(serverID: server, documents: (1...6).map { FileFixtures.doc($0) })
  }

  private func metadata(original: Int64, archive: Int64?) -> Metadata {
    Metadata(
      originalChecksum: "o", originalSize: original, originalMimeType: "application/pdf",
      mediaFilename: "f.pdf", hasArchiveVersion: archive != nil, originalMetadata: [],
      originalFilename: "f.pdf", archiveSize: archive, lang: "deu")
  }

  @Test("a document's size is its downloaded archive's, else what its metadata reports")
  func sizes() async throws {
    let database = try database()
    // Metadata with an archived version, and without one.
    try await database.setFileMetadata(
      metadata(original: 500, archive: 300), serverID: server, versionID: 1, documentModified: nil)
    try await database.setFileMetadata(
      metadata(original: 700, archive: nil), serverID: server, versionID: 2, documentModified: nil)
    // Downloaded: the file's own size wins over the metadata's.
    try await database.setFileMetadata(
      metadata(original: 50, archive: 40), serverID: server, versionID: 3, documentModified: nil)
    try await database.recordFile(
      FileFixtures.key(server, 3, .archive), documentID: 3, size: 4096, modified: nil,
      checksum: nil, storedAt: Date(), lastAccessedAt: nil)
    // An original alone says nothing about what the pass downloads.
    try await database.recordFile(
      FileFixtures.key(server, 4, .original), documentID: 4, size: 9999, modified: nil,
      checksum: nil, storedAt: Date(), lastAccessedAt: nil)
    for id in UInt(1)...2 {
      try await database.recordFile(
        FileFixtures.key(server, id, .thumbnail), documentID: id, size: 1000, modified: nil,
        checksum: nil, storedAt: Date(), lastAccessedAt: nil)
    }
    try await database.recordFile(
      FileFixtures.key(server, 1, .content), documentID: 1, size: 200, modified: nil,
      checksum: "c", storedAt: Date(), lastAccessedAt: nil)

    let sample = try await database.librarySizeSample(serverID: server)

    #expect(sample.documents == 6)
    #expect(sample.files == .init(documents: 3, bytes: 300 + 700 + 4096))
    #expect(sample.thumbnails == .init(documents: 2, bytes: 2000))
    #expect(sample.texts == .init(documents: 1, bytes: 200))
    #expect(sample.indexedDocuments == 0)
  }

  @Test("the documents without a known size are offered for sampling, the others not")
  func unknownSizes() async throws {
    let database = try database()
    try await database.setFileMetadata(
      metadata(original: 500, archive: 300), serverID: server, versionID: 1, documentModified: nil)
    try await database.recordFile(
      FileFixtures.key(server, 2, .archive), documentID: 2, size: 10, modified: nil,
      checksum: nil, storedAt: Date(), lastAccessedAt: nil)

    let all = try await database.documentIDsWithoutKnownFileSize(serverID: server, limit: 100)
    #expect(Set(all) == [3, 4, 5, 6])
    #expect(
      try await database.documentIDsWithoutKnownFileSize(serverID: server, limit: 2).count == 2)
  }

  @Test("another server's files are not counted")
  func scopedToServer() async throws {
    let database = try database()
    let other = UUID()
    try FileFixtures.addServer(other, to: database)
    try await database.upsertDocuments([FileFixtures.doc(1)], serverID: other)
    try await database.recordFile(
      FileFixtures.key(other, 1, .archive), documentID: 1, size: 10, modified: nil,
      checksum: nil, storedAt: Date(), lastAccessedAt: nil)

    let sample = try await database.librarySizeSample(serverID: server)
    #expect(sample.files == .init())
    #expect(sample.documents == 6)
  }

  @Test("the search index reports its documents and size across servers")
  func searchIndexUsage() async throws {
    let database = try database()
    try await database.recordFile(
      FileFixtures.key(server, 1, .content), documentID: 1, size: 10, modified: nil,
      checksum: "c", storedAt: Date(), lastAccessedAt: nil)
    let candidates = try await database.contentAwaitingIndex(limit: 10)
    try await database.indexContent(candidates.map { ($0, "zebrafink kolibri") })

    let usage = try await database.searchIndexUsage()
    #expect(usage.documents == 1)
    #expect(usage.bytes > 0)
    #expect(try await database.librarySizeSample(serverID: server).indexedDocuments == 1)
  }
}
