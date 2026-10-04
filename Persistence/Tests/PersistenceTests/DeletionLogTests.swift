import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// A list write carries a server answer computed before it was written. A
/// document deleted from the cache in between must not come back with it.
@Suite(
  "DeletionLog",
  .bug("https://github.com/paulgessinger/swift-paperless/issues/745", id: 745))
struct DeletionLogTests {
  private struct Rollback: Error {}

  private let key = QueryKey(sentinel: "list")

  private func doc(_ id: UInt, _ title: String = "Doc") -> Document {
    Document(
      id: id, title: title, asn: nil, created: Date(timeIntervalSince1970: 1000), tags: [],
      owner: .user(1))
  }

  /// A server with documents 1…3 cached and listed under `key`.
  private func database(_ server: UUID) async throws -> Persistence.Database {
    let database = try Database.seeded(serverID: server)
    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1), doc(2), doc(3)], totalCount: 3,
      basis: database.queryWriteBasis(queryKey: key, serverID: server))
    return database
  }

  private func entries(
    _ database: Persistence.Database, _ server: UUID
  ) async throws -> [DocumentEntry] {
    try await database.queryDocuments(queryKey: key, serverID: server, limit: 100)
  }

  private func positions(
    _ database: Persistence.Database, _ server: UUID
  ) async throws -> [UInt: Int] {
    try await database.writer.read { db in
      let rows =
        try QueryOrderRow
        .filter(Column("server_id") == server && Column("query_key") == key.rawValue)
        .fetchAll(db)
      return Dictionary(uniqueKeysWithValues: rows.map { ($0.remoteId, $0.position) })
    }
  }

  private func status(
    _ database: Persistence.Database, _ server: UUID
  ) async throws -> QueryStatus {
    try await database.queryStatus(queryKey: key, serverID: server)
  }

  // MARK: - Writes based on a mark from before the delete

  @Test("A membership rewrite leaves out an id deleted while its request was in flight")
  func replaceQueryOrderSkipsDeleted() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    #expect(
      try await database.replaceQueryOrder(
        queryKey: key, serverID: server, orderedIDs: [1, 2, 3], basis: basis))

    let entries = try await entries(database, server)
    #expect(entries.map(\.id) == [1, 3])
    #expect(entries.allSatisfy { $0.document != nil })
    #expect(try await positions(database, server) == [1: 0, 3: 1])
    let status = try await status(database, server)
    #expect(status.totalCount == 2)
    #expect(status.orderStale == false)
  }

  @Test("Page 1 of a fill doesn't re-create a document deleted while it was in flight")
  func replaceQueryPageSkipsDeleted() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    #expect(
      try await database.replaceQueryPage(
        queryKey: key, serverID: server, documents: [doc(1, "new"), doc(2), doc(3)],
        totalCount: 3, basis: basis))

    #expect(try await entries(database, server).map(\.id) == [1, 3])
    #expect(try await database.document(serverID: server, id: 2) == nil)
    #expect(try await database.document(serverID: server, id: 1)?.title == "new")
    // The server's positions and total, as the delete landing just after would leave them.
    #expect(try await positions(database, server) == [1: 0, 3: 2])
    #expect(try await status(database, server).totalCount == 3)
  }

  @Test("A later page of a fill doesn't re-create a document deleted since the fill began")
  func appendQueryPageSkipsDeleted() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1), doc(2)], totalCount: 4, basis: basis)
    try await database.deleteDocuments(serverID: server, removedIDs: [3])
    try await database.appendQueryPage(
      queryKey: key, serverID: server, documents: [doc(3), doc(4)], startPosition: 2,
      totalCount: 4, deletions: basis.deletions)

    #expect(try await entries(database, server).map(\.id) == [1, 2, 4])
    #expect(try await database.document(serverID: server, id: 3) == nil)
    #expect(try await positions(database, server) == [1: 0, 2: 1, 4: 3])
  }

  @Test("The changes delta doesn't re-create a document deleted while it was in flight")
  func applyChangedDocumentsSkipsDeleted() async throws {
    let server = UUID()
    let database = try await database(server)

    let mark = database.documentDeletionMark()
    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    try await database.applyChangedDocuments(
      [doc(1, "new"), doc(2, "new")], serverID: server, deletions: mark)

    #expect(try await database.document(serverID: server, id: 2) == nil)
    #expect(try await database.document(serverID: server, id: 1)?.title == "new")
  }

  // MARK: - Writes the log must not touch

  @Test("A write based on a mark from after the delete keeps an id the server lists again")
  func basisAfterDeleteUnaffected() async throws {
    let server = UUID()
    let database = try await database(server)

    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3], basis: basis)
    #expect(
      try await entries(database, server) == [.loaded(doc(1)), .skeleton(id: 2), .loaded(doc(3))])

    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1), doc(2), doc(3)], totalCount: 3,
      basis: database.queryWriteBasis(queryKey: key, serverID: server))
    #expect(try await database.document(serverID: server, id: 2) != nil)
  }

  @Test("A delete on another server leaves this server's writes alone")
  func otherServerUnaffected() async throws {
    let server = UUID()
    let database = try await database(server)
    let other = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: other, url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.deleteDocuments(serverID: other, removedIDs: [2])
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3], basis: basis)

    #expect(try await entries(database, server).map(\.id) == [1, 2, 3])
  }

  @Test("A delete that rolls back leaves the document in later writes")
  func rolledBackDeleteNotExcluded() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    await #expect(throws: Rollback.self) {
      try await database.writer.write { db in
        try Database.removeDocuments(
          db, serverID: server, removedIDs: [2], log: database.deletionLog)
        throw Rollback()
      }
    }
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3], basis: basis)

    let entries = try await entries(database, server)
    #expect(entries.map(\.id) == [1, 2, 3])
    #expect(entries.allSatisfy { $0.document != nil })
  }

  @Test("A document restored from the trash is no longer left out")
  func restoredDocumentNotExcluded() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    database.forgetDocumentDeletions([2], serverID: server)
    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1), doc(2), doc(3)], totalCount: 3,
      basis: basis)

    #expect(try await entries(database, server).map(\.id) == [1, 2, 3])
  }

  // MARK: - Bounded log

  @Test(
    "A mark the log has evicted past still leaves out what it retains, and marks the order stale")
  func evictedMarkFallsBackRetained() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    // One prune larger than the log: the oldest id is evicted, 2 is kept.
    let flood = (UInt(1000)..<UInt(1000 + DocumentDeletionLog.defaultCapacity))
    try await database.deleteDocuments(serverID: server, removedIDs: Array(flood) + [2])
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3], basis: basis)

    #expect(try await entries(database, server).map(\.id) == [1, 3])
    #expect(try await status(database, server).orderStale)
  }

  @Test("A mark the log can't check writes the answer whole and marks the order stale")
  func evictedMarkFallsBackStale() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    let flood = (UInt(1000)..<UInt(1000 + DocumentDeletionLog.defaultCapacity))
    try await database.deleteDocuments(serverID: server, removedIDs: [2] + Array(flood))
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 2, 3], basis: basis)
    #expect(try await entries(database, server).map(\.id) == [1, 2, 3])
    #expect(try await status(database, server).orderStale)

    // A fresh basis can be checked again, and clears the mark.
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1, 3],
      basis: database.queryWriteBasis(queryKey: key, serverID: server))
    #expect(try await status(database, server).orderStale == false)
  }

  @Test("Fill pages based on a mark the log can't check mark the order stale")
  func evictedMarkFallsBackStaleForPages() async throws {
    let server = UUID()
    let database = try await database(server)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    let flood = (UInt(1000)...UInt(1000 + DocumentDeletionLog.defaultCapacity))
    try await database.deleteDocuments(serverID: server, removedIDs: Array(flood))
    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1)], totalCount: 2, basis: basis)
    #expect(try await status(database, server).orderStale)

    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [doc(1)], totalCount: 2,
      basis: database.queryWriteBasis(queryKey: key, serverID: server))
    #expect(try await status(database, server).orderStale == false)
    try await database.appendQueryPage(
      queryKey: key, serverID: server, documents: [doc(2)], startPosition: 1, totalCount: 2,
      deletions: basis.deletions)
    #expect(try await status(database, server).orderStale)
  }

  // MARK: - The log itself

  @Test("Eviction makes marks from before the evicted entry incomplete")
  func logEviction() {
    let server = UUID()
    let log = DocumentDeletionLog(capacity: 2)
    let start = log.mark()
    log.record([1], serverID: server)
    let middle = log.mark()
    log.record([1], serverID: server)  // supersedes the first entry
    #expect(log.deleted(since: start, serverID: server) == .init(ids: [1], isComplete: true))

    log.record([2], serverID: server)  // evicts the superseded entry
    #expect(log.deleted(since: start, serverID: server) == .init(ids: [1, 2], isComplete: false))
    #expect(log.deleted(since: middle, serverID: server) == .init(ids: [1, 2], isComplete: true))

    log.record([3], serverID: server)  // evicts 1's live entry
    #expect(log.deleted(since: middle, serverID: server) == .init(ids: [2, 3], isComplete: false))
  }

  @Test("Discarding a rolled-back deletion falls back to the id's earlier deletion")
  func logDiscard() {
    let server = UUID()
    let log = DocumentDeletionLog()
    let start = log.mark()
    log.record([1], serverID: server)
    let middle = log.mark()
    let sequence = log.record([1, 2], serverID: server)
    log.discard(sequence: sequence)

    #expect(log.deleted(since: start, serverID: server) == .init(ids: [1], isComplete: true))
    #expect(log.deleted(since: middle, serverID: server) == .init(ids: [], isComplete: true))
  }

  @Test("A forgotten id stays forgotten when a later deletion of it rolls back")
  func logForgetThenDiscard() {
    let server = UUID()
    let log = DocumentDeletionLog()
    let start = log.mark()
    log.record([1], serverID: server)
    log.forget([1], serverID: server)
    log.discard(sequence: log.record([1], serverID: server))

    #expect(log.deleted(since: start, serverID: server).ids.isEmpty)
  }

  @Test("Dropping a server removes only its entries")
  func logDropServer() {
    let server = UUID()
    let other = UUID()
    let log = DocumentDeletionLog()
    let start = log.mark()
    log.record([1], serverID: server)
    log.record([2], serverID: other)
    log.drop(serverID: server)

    #expect(log.deleted(since: start, serverID: server).ids.isEmpty)
    #expect(log.deleted(since: start, serverID: other).ids == [2])
  }
}
