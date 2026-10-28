import Common
import DataModel
import Foundation
import Testing

@testable import Persistence

/// Which documents the library's file pass still has to download, and how
/// far it has come.
@Suite("Library files")
struct LibraryFilesTests {
  private let server = UUID()
  private func date(_ t: TimeInterval) -> Date { FileFixtures.date(t) }

  private func doc(_ id: UInt, modified: Date? = FileFixtures.date(500)) -> Document {
    FileFixtures.doc(id, modified: modified)
  }

  private func versioned(_ id: UInt, versions: [UInt]) -> Document {
    var document = FileFixtures.versioned(id, versions: versions)
    document.modified = date(500)
    return document
  }

  private func recordArchive(
    _ database: Database, _ id: UInt, version: UInt? = nil, modified: Date?, size: Int64 = 10,
    kind: ContentStore.Kind = .archive
  ) async throws {
    try await database.recordFile(
      FileFixtures.key(server, version ?? id, kind), documentID: id, size: size,
      modified: modified, checksum: nil, storedAt: date(1000), lastAccessedAt: nil)
  }

  /// The candidates that still need their archive.
  private func needingArchive(
    _ database: Database, scope: LibraryFileScope, excluding: Set<UInt> = [], limit: Int
  ) async throws -> [LibraryFileCandidate] {
    try await database.documentsNeedingFiles(
      serverID: server, scope: scope, excluding: excluding, limit: limit
    ).filter { $0.kinds.contains(.archive) }
  }

  @Test("A document is a candidate until its current version has a fresh archive")
  func candidates() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    // 1: fresh archive. 2: archive fetched against an older modified. 3: nothing.
    try await recordArchive(database, 1, modified: date(500))
    try await recordArchive(database, 2, modified: date(400))

    let ids = try await needingArchive(database, scope: .library, limit: 10)
      .map(\.documentID)
    #expect(ids == [3, 2])
  }

  @Test("An original does not stand in for the archive")
  func originalsDoNotCount() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try await recordArchive(database, 1, modified: date(500), kind: .original)

    let ids = try await needingArchive(database, scope: .library, limit: 10)
      .map(\.documentID)
    #expect(ids == [1])
  }

  @Test("Newest first, excluding what is downloading, up to the limit")
  func orderExclusionAndLimit() async throws {
    let database = try Database.seeded(
      serverID: server, documents: [doc(1), doc(2), doc(3), doc(4), doc(5)])

    let candidates = try await needingArchive(
      database, scope: .library, excluding: [5, 3], limit: 2)
    #expect(candidates.map(\.documentID) == [4, 2])
  }

  @Test("The candidate carries the version to file under and the one to request")
  func versions() async throws {
    let database = try Database.seeded(
      serverID: server,
      documents: [
        versioned(1, versions: [1, 9]),
        doc(2),
      ])

    let candidates = try await needingArchive(database, scope: .library, limit: 10)
    let versioned = try #require(candidates.first { $0.documentID == 1 })
    #expect(versioned.versionID == 9)
    #expect(versioned.versionQueryID == 9)
    #expect(versioned.modified == date(500))
    let plain = try #require(candidates.first { $0.documentID == 2 })
    #expect(plain.versionID == 2)
    #expect(plain.versionQueryID == nil)

    // Filed under the current version: the archive of version 9 satisfies it.
    try await recordArchive(database, 1, version: 9, modified: date(500))
    let after = try await needingArchive(database, scope: .library, limit: 10)
    #expect(after.map(\.documentID) == [2])
  }

  @Test("Documents without a modified, and other servers, are left out")
  func scope() async throws {
    let other = UUID()
    let database = try Database.seeded(
      serverID: server, documents: [doc(1, modified: nil), doc(2)])
    try FileFixtures.addServer(other, to: database)
    try await database.upsertDocuments([doc(3)], serverID: other)

    let ids = try await needingArchive(database, scope: .library, limit: 10)
      .map(\.documentID)
    #expect(ids == [2])
    let progress = try await database.libraryFileProgress(serverID: server, scope: .library)
    #expect(progress == LibraryFileProgress(totalDocuments: 1, downloadedFiles: 0))
  }

  @Test("Progress counts fresh archives and their bytes against the documents")
  func progress() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    try await recordArchive(database, 1, modified: date(500), size: 100)
    try await recordArchive(database, 2, modified: date(400), size: 50)
    try await recordArchive(database, 3, modified: date(500), size: 7, kind: .original)

    let progress = try await database.libraryFileProgress(serverID: server, scope: .library)
    #expect(
      progress == LibraryFileProgress(totalDocuments: 3, downloadedFiles: 1, downloadedBytes: 100))
  }

  @Test("The observation reports a recorded archive")
  func observation() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    var iterator = database.observeLibraryFileProgress(serverID: server, scope: .library)
      .makeAsyncIterator()
    let initial = try await iterator.next()
    #expect(initial == LibraryFileProgress(totalDocuments: 2))

    try await recordArchive(database, 1, modified: date(500), size: 100)
    let next = try await iterator.next()
    #expect(
      next == LibraryFileProgress(totalDocuments: 2, downloadedFiles: 1, downloadedBytes: 100))
  }

  @Test("The kept scope lists only members, cached or stale, and counts every member")
  func keptScope() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    // 1: kept, stale archive. 2: kept, fresh. 3: not kept, missing. 9: kept, no row.
    try await recordArchive(database, 1, modified: date(400))
    try await recordArchive(database, 2, modified: date(500), size: 7)
    for id: UInt in [1, 2, 9] {
      try await database.setKeptOffline(serverID: server, documentID: id, kept: true)
    }

    let kept = try await needingArchive(database, scope: .keptOffline, limit: 10).map(\.documentID)
    #expect(kept == [1])
    let library = try await needingArchive(database, scope: .library, limit: 10)
      .map(\.documentID)
    #expect(library == [3, 1])

    let progress = try await database.libraryFileProgress(serverID: server, scope: .keptOffline)
    #expect(
      progress == LibraryFileProgress(totalDocuments: 3, downloadedFiles: 1, downloadedBytes: 7))
    let whole = try await database.libraryFileProgress(serverID: server, scope: .library)
    #expect(whole == LibraryFileProgress(totalDocuments: 3, downloadedFiles: 1, downloadedBytes: 7))
  }

  @Test("A document is a candidate until its current version also has a thumbnail")
  func thumbnails() async throws {
    let database = try Database.seeded(
      serverID: server, documents: [doc(1), doc(2), versioned(3, versions: [3, 7])])
    // 1: fresh archive, no thumbnail. 2: both; the image cache records its
    // thumbnail without a modified. 3: a thumbnail of an older version only.
    try await recordArchive(database, 1, modified: date(500))
    try await recordArchive(database, 2, modified: date(500))
    try await recordArchive(database, 2, modified: nil, kind: .thumbnail)
    try await recordArchive(database, 3, version: 3, modified: nil, kind: .thumbnail)

    let candidates = try await database.documentsNeedingFiles(
      serverID: server, scope: .library, limit: 10)
    #expect(candidates.map(\.documentID) == [3, 1])
    #expect(candidates.map(\.kinds) == [[.archive, .thumbnail], [.thumbnail]])
  }

  // MARK: - Texts

  private func needingContent(
    _ database: Database, scope: LibraryFileScope, below: UInt? = nil, limit: Int = 10
  ) async throws -> [UInt] {
    try await database.documentsNeedingContent(
      serverID: server, scope: scope, below: below, limit: limit
    ).map(\.documentID)
  }

  @Test("A document needs its text until one is fetched against its modified")
  func contentCandidates() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    // 1: fresh text. 2: text fetched against an older modified. 3: only an archive.
    try await recordArchive(database, 1, modified: date(500), kind: .content)
    try await recordArchive(database, 2, modified: date(400), kind: .content)
    try await recordArchive(database, 3, modified: date(500))

    #expect(try await needingContent(database, scope: .library) == [3, 2])
    #expect(try await needingContent(database, scope: .library, below: 3, limit: 1) == [2])
    #expect(try await needingContent(database, scope: .library, below: 2).isEmpty)
    #expect(try await database.countDocumentsNeedingContent(serverID: server, scope: .library) == 2)
    let candidates = try await database.documentsNeedingContent(
      serverID: server, scope: .library, limit: 10)
    #expect(candidates.allSatisfy { $0.kinds == [.content] })
  }

  @Test("Any change to modified makes a text stale, a tag edit included")
  func contentGoesStale() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try await recordArchive(database, 1, modified: date(500), kind: .content)
    #expect(try await needingContent(database, scope: .library).isEmpty)

    var edited = doc(1, modified: date(600))
    edited.tags = [7]
    try await database.upsertDocuments([edited], serverID: server)
    #expect(try await needingContent(database, scope: .library) == [1])
  }

  @Test("A text is filed under the current version, and kept scope is the kept documents")
  func contentVersionsAndScope() async throws {
    let database = try Database.seeded(
      serverID: server, documents: [versioned(1, versions: [1, 9]), doc(2), doc(3, modified: nil)])
    try await recordArchive(database, 1, version: 1, modified: date(500), kind: .content)
    #expect(try await needingContent(database, scope: .library) == [2, 1])
    try await recordArchive(database, 1, version: 9, modified: date(500), kind: .content)
    #expect(try await needingContent(database, scope: .library) == [2])

    #expect(try await needingContent(database, scope: .keptOffline).isEmpty)
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true)
    #expect(try await needingContent(database, scope: .keptOffline) == [2])
    #expect(
      try await database.countDocumentsNeedingContent(serverID: server, scope: .keptOffline) == 1)
  }
}
