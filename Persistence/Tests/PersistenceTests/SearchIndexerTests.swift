import Common
import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Search indexer")
struct SearchIndexerTests {
  private let server = UUID()

  private func setup(documents: Int = 5) throws -> (Persistence.Database, ContentStore) {
    let database = try Database.seeded(
      serverID: server, documents: (1...documents).map { FileFixtures.doc(UInt($0)) })
    return (database, try FileFixtures.makeStore())
  }

  /// Store `text` as `document`'s text, file and row, like `ApiRepository`.
  private func store(
    _ text: String, for document: UInt, in store: ContentStore, _ database: Persistence.Database,
    storedAt: Date = Date()
  ) async throws {
    let key = FileFixtures.key(server, document, .content)
    try store.storeText(text, for: key)
    try await database.recordFile(
      key, documentID: document, size: store.size(of: key) ?? 0, modified: nil,
      checksum: ContentStore.checksum(of: text), storedAt: storedAt, lastAccessedAt: nil)
  }

  private func found(_ database: Persistence.Database, _ word: String) async throws -> [UInt] {
    let filter = FilterState.empty.with {
      $0.searchMode = .titleContent
      $0.searchText = word
      $0.sorting = .init(field: .created, order: .descending)
    }
    let key = QueryKey(serverID: server, filter: filter)
    try await database.evaluateQueryLocally(filter: filter, queryKey: key, serverID: server)
    return try await database.queryDocuments(queryKey: key, serverID: server, limit: 1000)
      .map(\.id).sorted()
  }

  @Test("a pass indexes the stored texts and makes them searchable")
  func indexesStoredTexts() async throws {
    let (database, store) = try setup()
    try await self.store("Der zebrafink singt", for: 1, in: store, database)
    try await self.store("Ein kolibri schwebt", for: 2, in: store, database)

    let report = await SearchIndexer(database: database, store: store).run()

    #expect(report == .init(indexed: 2, unreadable: 0))
    #expect(try await found(database, "zebrafink") == [1])
    #expect(try await found(database, "kolibri") == [2])
    #expect(await SearchIndexer(database: database, store: store).run().indexed == 0)
  }

  @Test("a backlog larger than one batch is indexed in one pass")
  func indexesBacklog() async throws {
    let count = SearchIndexer.Batch.candidates * 3 + 7
    let (database, store) = try setup(documents: count)
    for id in 1...count {
      try await self.store(
        "wort\(id) gemeinsam", for: UInt(id), in: store, database,
        storedAt: Date(timeIntervalSinceReferenceDate: Double(id)))
    }

    let report = await SearchIndexer(database: database, store: store).run()

    #expect(report.indexed == count)
    #expect(try await found(database, "gemeinsam").count == count)
    #expect(try await found(database, "wort\(count)") == [UInt(count)])
  }

  @Test("a text whose file is missing is skipped and the rest is indexed")
  func skipsUnreadable() async throws {
    let (database, store) = try setup()
    try await self.store("zebrafink", for: 1, in: store, database)
    // A row with no file behind it.
    try await database.recordFile(
      FileFixtures.key(server, 2, .content), documentID: 2, size: 1, modified: nil,
      checksum: "c", storedAt: Date().addingTimeInterval(10), lastAccessedAt: nil)

    let report = await SearchIndexer(database: database, store: store).run()

    #expect(report == .init(indexed: 1, unreadable: 1))
    #expect(try await found(database, "zebrafink") == [1])
  }

  @Test("a replaced text is picked up by the next pass")
  func picksUpReplacedText() async throws {
    let (database, store) = try setup()
    let indexer = SearchIndexer(database: database, store: store)
    try await self.store("zebrafink", for: 1, in: store, database)
    await indexer.run()

    try await self.store("kolibri", for: 1, in: store, database, storedAt: Date())
    await indexer.run()

    #expect(try await found(database, "zebrafink").isEmpty)
    #expect(try await found(database, "kolibri") == [1])
  }

  @Test("following the file index indexes a text stored later")
  func followsFileIndex() async throws {
    let (database, store) = try setup()
    let indexer = SearchIndexer(database: database, store: store)
    await indexer.follow()
    try await self.store("zebrafink", for: 3, in: store, database)

    var indexed = false
    for _ in 0..<100 where !indexed {
      try await Task.sleep(for: .milliseconds(50))
      indexed = try await database.searchIndexCoverage(serverID: server).indexedDocuments == 1
    }
    await indexer.stop()
    #expect(indexed)
  }

  @Test("without a store there is nothing to index")
  func withoutStore() async throws {
    let (database, _) = try setup()
    try await database.recordFile(
      FileFixtures.key(server, 1, .content), documentID: 1, size: 1, modified: nil,
      checksum: "c", storedAt: Date(), lastAccessedAt: nil)
    #expect(await SearchIndexer(database: database, store: nil).run() == .init())
  }
}
