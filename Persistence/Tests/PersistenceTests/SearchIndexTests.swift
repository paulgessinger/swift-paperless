import Common
import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Search index")
struct SearchIndexTests {
  private let server = UUID()

  private func database() throws -> Persistence.Database {
    try Database.seeded(
      serverID: server, documents: (1...5).map { FileFixtures.doc($0) })
  }

  /// A `content` file row for `document`, as storing its text leaves it.
  private func storeText(
    _ database: Persistence.Database, document: UInt, version: UInt? = nil,
    checksum: String? = "c1", storedAt: TimeInterval = 100, server: UUID? = nil
  ) async throws {
    try await database.recordFile(
      FileFixtures.key(server ?? self.server, version ?? document, .content),
      documentID: document, size: 10, modified: nil, checksum: checksum,
      storedAt: FileFixtures.date(storedAt), lastAccessedAt: nil)
  }

  /// Index every awaiting text with what `text` gives for its document.
  @discardableResult
  private func index(
    _ database: Persistence.Database, _ text: (UInt) -> String
  ) async throws -> Int {
    let candidates = try await database.contentAwaitingIndex(limit: 100)
    return try await database.indexContent(candidates.map { ($0, text($0.documentID)) })
  }

  private func matches(_ database: Persistence.Database, _ query: String) async throws -> Set<UInt>
  {
    try await database.writer.read { db in
      try UInt.fetchSet(
        db,
        sql: """
          SELECT ci.document_id FROM content_fts
          JOIN content_index ci ON ci.id = content_fts.rowid
          WHERE content_fts MATCH ?
          """, arguments: [query])
    }
  }

  private func indexRows(_ database: Persistence.Database) async throws -> Int {
    try await database.writer.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM content_index") ?? 0
    }
  }

  @Test("a stored text awaits indexing until it is indexed")
  func awaitsUntilIndexed() async throws {
    let database = try database()
    try await storeText(database, document: 1)
    try await storeText(database, document: 2)
    // Other kinds are not texts.
    try await database.recordFile(
      FileFixtures.key(server, 3, .archive), documentID: 3, size: 10, modified: nil,
      checksum: nil, storedAt: Date(), lastAccessedAt: nil)

    #expect(Set(try await database.contentAwaitingIndex(limit: 10).map(\.documentID)) == [1, 2])
    #expect(try await index(database) { "text of document \($0)" } == 2)
    #expect(try await database.contentAwaitingIndex(limit: 10).isEmpty)
    #expect(
      try await database.searchIndexCoverage(serverID: server)
        == SearchIndexCoverage(indexedDocuments: 2, awaitingIndex: 0, documents: 5))
  }

  @Test("indexed text is found by word prefix, ignoring case and diacritics")
  func findsByPrefix() async throws {
    let database = try database()
    try await storeText(database, document: 1)
    try await storeText(database, document: 2)
    try await index(database) {
      $0 == 1 ? "Die Haftpflichtversicherung für München" : "Telekom Rechnung März 2024"
    }

    #expect(try await matches(database, "\"haftpfl\"*") == [1])
    #expect(try await matches(database, "\"munchen\"*") == [1])
    #expect(try await matches(database, "\"telekom\"* AND \"rech\"*") == [2])
    #expect(try await matches(database, "\"versicherung\"*").isEmpty)
  }

  @Test("a replaced text is indexed again and the old words are gone")
  func reindexesReplacedText() async throws {
    let database = try database()
    try await storeText(database, document: 1, checksum: "old")
    try await index(database) { _ in "zebrafink" }

    // Same key, new text.
    try await storeText(database, document: 1, checksum: "new", storedAt: 200)
    #expect(try await database.contentAwaitingIndex(limit: 10).count == 1)
    try await index(database) { _ in "kolibri" }

    #expect(try await matches(database, "\"zebrafink\"").isEmpty)
    #expect(try await matches(database, "\"kolibri\"") == [1])
    #expect(try await indexRows(database) == 1)
  }

  @Test("a text stored again unchanged is not indexed again")
  func skipsUnchangedText() async throws {
    let database = try database()
    try await storeText(database, document: 1, checksum: "same", storedAt: 100)
    try await index(database) { _ in "zebrafink" }
    // Re-dated, as an unchanged text is (`ApiRepository.storeText`).
    try await storeText(database, document: 1, checksum: "same", storedAt: 200)

    #expect(try await database.contentAwaitingIndex(limit: 10).isEmpty)
  }

  @Test("a file without a checksum is indexed again when it is stored again")
  func adoptedFileFollowsStoredAt() async throws {
    let database = try database()
    try await storeText(database, document: 1, checksum: nil, storedAt: 100)
    try await index(database) { _ in "zebrafink" }
    #expect(try await database.contentAwaitingIndex(limit: 10).isEmpty)

    try await storeText(database, document: 1, checksum: nil, storedAt: 200)
    #expect(try await database.contentAwaitingIndex(limit: 10).count == 1)
  }

  @Test("a new version's text replaces the old version's entry")
  func newVersionReplacesEntry() async throws {
    let database = try database()
    try await storeText(database, document: 1, version: 1)
    try await index(database) { _ in "zebrafink" }
    try await storeText(database, document: 1, version: 9, storedAt: 200)
    try await index(database) { _ in "kolibri" }

    #expect(try await indexRows(database) == 1)
    #expect(try await matches(database, "\"kolibri\"") == [1])
    // The superseded version's file going leaves the new entry alone.
    try await database.deleteFile(FileFixtures.key(server, 1, .content))
    #expect(try await matches(database, "\"kolibri\"") == [1])
  }

  @Test("a candidate whose file changed since it was read is skipped")
  func skipsOutdatedCandidate() async throws {
    let database = try database()
    try await storeText(database, document: 1, checksum: "old", storedAt: 100)
    let candidates = try await database.contentAwaitingIndex(limit: 10)
    try await storeText(database, document: 1, checksum: "new", storedAt: 200)

    #expect(try await database.indexContent(candidates.map { ($0, "zebrafink") }) == 0)
    #expect(try await matches(database, "\"zebrafink\"").isEmpty)
    #expect(try await database.contentAwaitingIndex(limit: 10).count == 1)
  }

  @Test("deleting a text's file row removes it from the index")
  func deletingFileRemovesEntry() async throws {
    let database = try database()
    try await storeText(database, document: 1)
    try await storeText(database, document: 2)
    try await index(database) { "zebrafink \($0)" }

    try await database.deleteFile(FileFixtures.key(server, 1, .content))

    #expect(try await matches(database, "\"zebrafink\"") == [2])
    #expect(try await indexRows(database) == 1)
  }

  @Test("clearing the cache empties the index")
  func clearCacheEmptiesIndex() async throws {
    let database = try database()
    try await storeText(database, document: 1)
    try await index(database) { _ in "zebrafink" }

    try await database.clearCache()

    #expect(try await indexRows(database) == 0)
    #expect(try await matches(database, "\"zebrafink\"").isEmpty)
  }

  @Test("removing a server removes its entries and their texts")
  func removingServerRemovesEntries() async throws {
    let database = try database()
    let other = UUID()
    try FileFixtures.addServer(other, to: database)
    try await database.upsertDocuments([FileFixtures.doc(1)], serverID: other)
    try await storeText(database, document: 1)
    try await storeText(database, document: 1, server: other)
    try await index(database) { _ in "zebrafink" }
    #expect(try await indexRows(database) == 2)

    _ = try database.deleteConnection(id: other)

    #expect(try await indexRows(database) == 1)
    // The text went with its entry: one match is left, not a dangling rowid.
    let rowids = try await database.writer.read { db in
      try Int.fetchAll(db, sql: "SELECT rowid FROM content_fts WHERE content_fts MATCH 'zebrafink'")
    }
    #expect(rowids.count == 1)
  }

  @Test("the index reports its size and survives an optimize")
  func sizeAndOptimize() async throws {
    let database = try database()
    for id in UInt(1)...5 {
      try await storeText(database, document: id)
    }
    try await index(database) { "wort\($0) " + String(repeating: "lorem ipsum dolor ", count: 50) }

    #expect(try await database.searchIndexBytes() > 0)
    try await database.optimizeSearchIndex()
    #expect(try await matches(database, "\"wort3\"") == [3])
  }
}
