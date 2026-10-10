import Common
import DataModel
import Foundation
import Testing

@testable import Persistence

/// The file index (`file`): the rows behind the content store's blobs, the
/// freshness lookup, the eviction order and the repair walk's adoption.
@Suite("File index")
struct FileIndexTests {
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt, modified: Date? = nil) -> Document {
    Document(
      id: id, title: "d\(id)", created: date(1000), tags: [], modified: modified, owner: .user(1))
  }

  private func versioned(_ id: UInt, versions: [UInt]) -> Document {
    Document(
      id: id, title: "v", created: date(1000), tags: [], owner: .user(1),
      versions: versions.map {
        DocumentVersion(id: $0, added: date(1000), isRoot: $0 == versions.first)
      })
  }

  private func addServer(_ id: UUID, to database: Database) throws {
    try database.upsertConnection(
      ConnectionRecord(
        id: id,
        url: URL(string: "https://\(id.uuidString).example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))
  }

  private func key(_ server: UUID, _ version: UInt, _ kind: ContentStore.Kind = .archive)
    -> ContentStore.Key
  {
    ContentStore.Key(serverID: server, versionID: version, kind: kind)
  }

  /// Insert an archive row accessed at `accessed`, for the eviction tests.
  private func record(
    _ database: Database, _ key: ContentStore.Key, size: Int64, accessed: Date
  ) async throws {
    try await database.recordFile(
      key, documentID: key.versionID, size: size, modified: nil, checksum: nil,
      storedAt: accessed, lastAccessedAt: accessed)
  }

  // MARK: - Rows

  @Test("A row is fresh for the modified it was fetched against, and only that")
  func freshness() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let key = key(server, 1)

    #expect(try await database.freshFile(key, modified: date(5000)) == nil)

    try await database.recordFile(
      key, documentID: 1, size: 100, modified: date(5000), checksum: "abc", storedAt: date(6000),
      lastAccessedAt: date(6000))

    let fresh = try #require(try await database.freshFile(key, modified: date(5000)))
    #expect(fresh.documentId == 1)
    #expect(fresh.size == 100)
    #expect(fresh.checksum == "abc")
    #expect(fresh.storedAt == date(6000).timeIntervalSinceReferenceDate)
    #expect(try await database.freshFile(key, modified: date(5000.5)) == nil)
    // Another kind of the same version is its own row.
    #expect(
      try await database.freshFile(self.key(server, 1, .original), modified: date(5000)) == nil)
  }

  @Test("Recording the same key again replaces the row and reports the evictable total")
  func upsert() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let key = key(server, 1)

    let first = try await database.recordFile(
      key, documentID: 1, size: 100, modified: date(1), checksum: nil, storedAt: date(1),
      lastAccessedAt: date(1))
    #expect(first == 100)
    let second = try await database.recordFile(
      key, documentID: 1, size: 250, modified: date(2), checksum: nil, storedAt: date(2),
      lastAccessedAt: date(2))
    #expect(second == 250)
    // Thumbnails are indexed but never count.
    let third = try await database.recordFile(
      self.key(server, 1, .thumbnail), documentID: 1, size: 9_999, modified: nil, checksum: nil,
      storedAt: date(3), lastAccessedAt: nil)
    #expect(third == 250)

    #expect(try await database.freshFile(key, modified: date(1)) == nil)
    #expect(try await database.freshFile(key, modified: date(2))?.size == 250)
    #expect(try await database.evictableFileBytes() == 250)
    #expect(try await database.allFileKeys() == [key, self.key(server, 1, .thumbnail)])
  }

  @Test("Touching a row moves its access stamp")
  func touch() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let key = key(server, 1)
    try await record(database, key, size: 1, accessed: date(1000))

    try await database.touchFile(key, at: date(2000))

    let row = try #require(try await database.anyFile(key))
    #expect(row.lastAccessedAt == date(2000).timeIntervalSinceReferenceDate)
  }

  @Test("deleteFiles leaves a row that was re-written since it was read")
  func deleteMatchesStoredAt() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    try await record(database, key(server, 1), size: 1, accessed: date(1000))
    try await record(database, key(server, 2), size: 1, accessed: date(1000))
    let read = try await database.unreferencedFilesForTest()

    // Version 2 was downloaded again in between.
    try await record(database, key(server, 2), size: 2, accessed: date(3000))
    let deleted = try await database.deleteFiles(read)

    #expect(deleted == 1)
    #expect(try await database.allFileKeys() == [key(server, 2)])
  }

  // MARK: - Reachability

  @Test("unreferencedFiles lists rows whose version no cached document is at")
  func unreferenced() async throws {
    let server = UUID()
    let other = UUID()
    let database = try Database.seeded(
      serverID: server, documents: [versioned(1, versions: [1, 9]), doc(2)])
    try addServer(other, to: database)
    try await database.upsertDocuments([doc(1)], serverID: other)
    for key in [
      key(server, 1), key(server, 9), key(server, 9, .thumbnail), key(server, 2), key(server, 7),
      key(other, 1), key(other, 2),
    ] {
      try await record(database, key, size: 1, accessed: date(1000))
    }

    let unreferenced = try await database.unreferencedFiles()

    #expect(Set(unreferenced.compactMap(\.key)) == [key(server, 1), key(server, 7), key(other, 2)])
  }

  @Test("Removing a connection drops its rows")
  func cascadeOnServerDelete() async throws {
    let server = UUID()
    let other = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try addServer(other, to: database)
    try await record(database, key(server, 1), size: 1, accessed: date(1000))
    try await record(database, key(other, 1), size: 1, accessed: date(1000))

    _ = try database.deleteConnection(id: other)

    #expect(try await database.allFileKeys() == [key(server, 1)])
  }

  @Test("clearCache empties the index")
  func clearing() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try await record(database, key(server, 1), size: 1, accessed: date(1000))

    try await database.clearCache()

    #expect(try await database.allFileKeys().isEmpty)
  }

  // MARK: - Eviction

  @Test("Eviction candidates are the least recently accessed, down to the budget")
  func evictionOrder() async throws {
    let server = UUID()
    let database = try Database.seeded(
      serverID: server, documents: [doc(1), doc(2), doc(3), doc(4)])
    try await record(database, key(server, 1), size: 40, accessed: date(3000))
    try await record(database, key(server, 2), size: 40, accessed: date(1000))
    try await record(database, key(server, 3), size: 40, accessed: date(2000))
    try await record(database, key(server, 4), size: 40, accessed: date(4000))
    try await database.recordFile(
      key(server, 4, .thumbnail), documentID: 4, size: 1_000, modified: nil, checksum: nil,
      storedAt: date(1), lastAccessedAt: nil)

    // 160 evictable bytes; two have to go.
    let candidates = try await database.evictionCandidates(
      budget: 80, protectAccessedAfter: date(9000))

    #expect(candidates.compactMap(\.key) == [key(server, 2), key(server, 3)])
    #expect(
      try await database.evictionCandidates(budget: 160, protectAccessedAfter: date(9000)).isEmpty)
  }

  @Test("A file accessed inside the protection window stops the eviction")
  func recentAccessGuard() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    try await record(database, key(server, 1), size: 40, accessed: date(1000))
    try await record(database, key(server, 2), size: 40, accessed: date(5000))
    try await record(database, key(server, 3), size: 40, accessed: date(6000))

    let candidates = try await database.evictionCandidates(
      budget: 10, protectAccessedAfter: date(4500))

    #expect(candidates.compactMap(\.key) == [key(server, 1)])
  }

  @Test("The most recently accessed file stays even when it alone exceeds the budget")
  func largeFileStays() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    try await record(database, key(server, 1), size: 10, accessed: date(1000))
    try await record(database, key(server, 2), size: 900, accessed: date(2000))

    let candidates = try await database.evictionCandidates(
      budget: 100, protectAccessedAfter: date(9000))

    #expect(candidates.compactMap(\.key) == [key(server, 1)])
  }

  // MARK: - Adoption

  @Test("adoptFiles enters files under a live version and reports the rest")
  func adoption() async throws {
    let server = UUID()
    let database = try Database.seeded(
      serverID: server, documents: [versioned(1, versions: [1, 9]), doc(2)])

    let unresolved = try await database.adoptFiles([
      FileAdoption(
        key: key(server, 9), size: 500, modified: date(5000), storedAt: date(6000),
        lastAccessedAt: date(7000)),
      FileAdoption(
        key: key(server, 2, .original), size: 10, modified: nil, storedAt: date(6000),
        lastAccessedAt: nil),
      FileAdoption(
        key: key(server, 1), size: 1, modified: nil, storedAt: date(1), lastAccessedAt: nil),
      FileAdoption(
        key: key(server, 42), size: 1, modified: nil, storedAt: date(1), lastAccessedAt: nil),
    ])

    #expect(unresolved == [key(server, 1), key(server, 42)])
    let adopted = try #require(try await database.freshFile(key(server, 9), modified: date(5000)))
    #expect(adopted.documentId == 1)
    #expect(adopted.size == 500)
    #expect(adopted.storedAt == date(6000).timeIntervalSinceReferenceDate)
    #expect(adopted.lastAccessedAt == date(7000).timeIntervalSinceReferenceDate)
    #expect(try await database.allFileKeys() == [key(server, 9), key(server, 2, .original)])
  }

  // MARK: - Usage

  @Test("fileUsage sums sizes per server, thumbnails apart")
  func usage() async throws {
    let server = UUID()
    let other = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try addServer(other, to: database)
    try await record(database, key(server, 1), size: 100, accessed: date(1))
    try await record(database, key(server, 1, .original), size: 300, accessed: date(1))
    try await record(database, key(other, 1), size: 50, accessed: date(1))
    try await database.recordFile(
      key(server, 1, .thumbnail), documentID: 1, size: 7, modified: nil, checksum: nil,
      storedAt: date(1), lastAccessedAt: nil)

    let usage = try await database.fileUsage()

    #expect(usage.documents == DiskUsage(bytes: 450, files: 3))
    #expect(usage.documentsByServer[server] == DiskUsage(bytes: 400, files: 2))
    #expect(usage.documentsByServer[other] == DiskUsage(bytes: 50, files: 1))
    #expect(usage.thumbnails == DiskUsage(bytes: 7, files: 1))
    #expect(try await Database.seeded().fileUsage() == FileUsage())
  }
}

extension Database {
  /// Every row, in the shape the reclaim reads them.
  fileprivate func unreferencedFilesForTest() async throws -> [FileRecord] {
    try await writer.read { db in try FileRecord.fetchAll(db) }
  }

  /// The row for `key` whatever it was fetched against.
  fileprivate func anyFile(_ key: ContentStore.Key) async throws -> FileRecord? {
    try await writer.read { db in try FileRecord.fetchAll(db) }.first { $0.key == key }
  }
}
