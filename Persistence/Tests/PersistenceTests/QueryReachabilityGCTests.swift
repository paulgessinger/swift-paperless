import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The reachability GC for cached query keys (#669): the mechanism half only —
/// *which* keys are reachable is the caching repository's policy and lives in
/// `AppShared`. What is asserted here is that the accessor keeps exactly what it
/// is told to keep, forgets the rest across all three query tables, stays inside
/// one server, commits once, and leaves the documents it freed prunable.
@Suite("QueryReachabilityGC")
struct QueryReachabilityGCTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt, _ title: String) -> Document {
    Document(id: id, title: title, created: date(1000), tags: [], owner: .user(1))
  }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  private func key(_ name: String) -> QueryKey { QueryKey(sentinel: name) }

  /// Stamp a key's `filled_at` directly. `markQueryFillComplete` always stamps
  /// *now*, so an LRU test that wants an ordering has to write the times itself.
  private func setFilledAt(
    _ filledAt: Date?, key: QueryKey, serverID: UUID, on database: Persistence.Database
  ) throws {
    try database.writer.write { db in
      try db.execute(
        sql: "UPDATE query_meta SET filled_at = ? WHERE server_id = ? AND query_key = ?",
        arguments: [filledAt, serverID, key.rawValue])
    }
  }

  /// Non-`async` on purpose: inside an `async` test `writer.write` resolves to
  /// the `async` overload, which this deliberately is not.
  private func deleteMeta(_ database: Persistence.Database, _ serverID: UUID) throws {
    try database.writer.write { db in
      try db.execute(sql: "DELETE FROM query_meta WHERE server_id = ?", arguments: [serverID])
    }
  }

  private func orderKeys(_ database: Persistence.Database, _ serverID: UUID) throws -> Set<String> {
    try database.writer.read { db in
      try String.fetchSet(
        db, sql: "SELECT DISTINCT query_key FROM query_order WHERE server_id = ?",
        arguments: [serverID])
    }
  }

  private func metaKeys(_ database: Persistence.Database, _ serverID: UUID) throws -> Set<String> {
    try database.writer.read { db in
      try String.fetchSet(
        db, sql: "SELECT query_key FROM query_meta WHERE server_id = ?", arguments: [serverID])
    }
  }

  private func errorKeys(_ database: Persistence.Database, _ serverID: UUID) throws -> Set<String> {
    try database.writer.read { db in
      try String.fetchSet(
        db, sql: "SELECT query_key FROM query_sync_error WHERE server_id = ?",
        arguments: [serverID])
    }
  }

  /// Counts committed transactions, so "one transaction" can be asserted
  /// directly — the same technique as `AtomicCacheUpdateTests`, and for the same
  /// reason: an in-memory `DatabaseQueue` serializes everything, so a concurrent
  /// writer can't be staged, and the commit count is what closes the window.
  private final class CommitCounter: TransactionObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var _commits = 0

    var commits: Int {
      lock.lock()
      defer { lock.unlock() }
      return _commits
    }

    func reset() {
      lock.lock()
      _commits = 0
      lock.unlock()
    }

    func observes(eventsOfKind _: DatabaseEventKind) -> Bool { true }
    func databaseDidChange(with _: DatabaseEvent) {}
    func databaseDidRollback(_: GRDB.Database) {}

    func databaseDidCommit(_: GRDB.Database) {
      lock.lock()
      _commits += 1
      lock.unlock()
    }
  }

  private func countingCommits(on database: Persistence.Database) throws -> CommitCounter {
    let counter = CommitCounter()
    try database.writer.write { db in
      db.add(transactionObserver: counter, extent: .databaseLifetime)
    }
    counter.reset()
    return counter
  }

  // MARK: - pruneUnreachableQueries

  @Test("keeps the reachable keys and drops the rest from all three query tables")
  func dropsUnreachableAcrossEveryTable() async throws {
    let server = UUID()
    let database = try database(server)
    let keep = key("keep")
    let drop = key("drop")

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    try await database.replaceQueryOrder(queryKey: keep, serverID: server, orderedIDs: [1])
    try await database.replaceQueryOrder(queryKey: drop, serverID: server, orderedIDs: [2])
    try await database.recordQuerySyncError(
      serverID: server, queryKey: keep.rawValue, savedViewName: "Keep", message: "boom")
    try await database.recordQuerySyncError(
      serverID: server, queryKey: drop.rawValue, savedViewName: "Drop", message: "boom")

    let collected = try await database.pruneUnreachableQueries(
      serverID: server, reachableKeys: [keep])

    #expect(collected == 1)
    #expect(try orderKeys(database, server) == ["keep"])
    #expect(try metaKeys(database, server) == ["keep"])
    #expect(try errorKeys(database, server) == ["keep"])
  }

  @Test("is a no-op — and reports zero — when every key is reachable")
  func noOpWhenEverythingReachable() async throws {
    let server = UUID()
    let database = try database(server)
    let a = key("a")
    let b = key("b")

    try await database.upsertDocuments([doc(1, "A")], serverID: server)
    try await database.replaceQueryOrder(queryKey: a, serverID: server, orderedIDs: [1])
    try await database.replaceQueryOrder(queryKey: b, serverID: server, orderedIDs: [1])

    #expect(
      try await database.pruneUnreachableQueries(serverID: server, reachableKeys: [a, b]) == 0)
    #expect(try orderKeys(database, server) == ["a", "b"])
  }

  @Test("an empty reachable set drops the server's whole query cache")
  func emptyReachableSetDropsEverything() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments([doc(1, "A")], serverID: server)
    try await database.replaceQueryOrder(queryKey: key("a"), serverID: server, orderedIDs: [1])
    try await database.recordQuerySyncError(
      serverID: server, queryKey: key("b").rawValue, savedViewName: nil, message: "boom")

    #expect(
      try await database.pruneUnreachableQueries(serverID: server, reachableKeys: []) == 2)
    #expect(try orderKeys(database, server).isEmpty)
    #expect(try metaKeys(database, server).isEmpty)
    #expect(try errorKeys(database, server).isEmpty)
  }

  @Test("is scoped to one server")
  func scopedToOneServer() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    // The *same* key on both servers, unreachable on A and reachable on B.
    let shared = key("shared")
    try await database.upsertDocuments([doc(1, "A")], serverID: serverA)
    try await database.upsertDocuments([doc(1, "A")], serverID: serverB)
    try await database.replaceQueryOrder(queryKey: shared, serverID: serverA, orderedIDs: [1])
    try await database.replaceQueryOrder(queryKey: shared, serverID: serverB, orderedIDs: [1])

    let collected = try await database.pruneUnreachableQueries(
      serverID: serverA, reachableKeys: [])

    #expect(collected == 1)
    #expect(try orderKeys(database, serverA).isEmpty)
    #expect(try orderKeys(database, serverB) == ["shared"])
    #expect(try metaKeys(database, serverB) == ["shared"])
  }

  @Test("takes exactly one transaction")
  func singleTransaction() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    try await database.replaceQueryOrder(queryKey: key("keep"), serverID: server, orderedIDs: [1])
    try await database.replaceQueryOrder(queryKey: key("drop"), serverID: server, orderedIDs: [2])
    try await database.recordQuerySyncError(
      serverID: server, queryKey: key("drop").rawValue, savedViewName: nil, message: "boom")

    let counter = try countingCommits(on: database)
    try await database.pruneUnreachableQueries(serverID: server, reachableKeys: [key("keep")])

    #expect(counter.commits == 1)
  }

  @Test("frees documents that only the orphaned key was pinning")
  func unblocksDocumentPruning() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)
    try await database.replaceQueryOrder(queryKey: key("keep"), serverID: server, orderedIDs: [1])
    try await database.replaceQueryOrder(queryKey: key("drop"), serverID: server, orderedIDs: [2])

    // Before the sweep the orphaned key still "references" document 2.
    #expect(try await database.pruneUnreferencedDocuments(serverID: server) == 0)

    try await database.pruneUnreachableQueries(serverID: server, reachableKeys: [key("keep")])

    #expect(try await database.pruneUnreferencedDocuments(serverID: server) == 1)
    #expect(try await database.document(serverID: server, id: 1) != nil)
    #expect(try await database.document(serverID: server, id: 2) == nil)
  }

  // MARK: - cachedQueries

  @Test("reports every key with rows, with its completed-fill stamp")
  func reportsCachedQueries() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments([doc(1, "A")], serverID: server)
    try await database.replaceQueryOrder(queryKey: key("filled"), serverID: server, orderedIDs: [1])
    try await database.replaceQueryOrder(
      queryKey: key("unfilled"), serverID: server, orderedIDs: [1])
    try setFilledAt(date(5000), key: key("filled"), serverID: server, on: database)

    let cached = try await database.cachedQueries(serverID: server)

    #expect(Set(cached.map(\.key.rawValue)) == ["filled", "unfilled"])
    #expect(cached.first { $0.key == key("filled") }?.filledAt == date(5000))
    #expect(cached.first { $0.key == key("unfilled") }?.filledAt == nil)
  }

  @Test("sees a key that has membership rows but no meta row")
  func seesOrderOnlyKey() async throws {
    let server = UUID()
    let database = try database(server)

    try await database.upsertDocuments([doc(1, "A")], serverID: server)
    try await database.replaceQueryOrder(queryKey: key("a"), serverID: server, orderedIDs: [1])
    try deleteMeta(database, server)

    let cached = try await database.cachedQueries(serverID: server)

    #expect(cached.map(\.key.rawValue) == ["a"])
    #expect(cached.first?.filledAt == nil)
  }

  @Test("is scoped to one server")
  func cachedQueriesScopedToOneServer() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))

    try await database.upsertDocuments([doc(1, "A")], serverID: serverA)
    try await database.upsertDocuments([doc(1, "A")], serverID: serverB)
    try await database.replaceQueryOrder(queryKey: key("a"), serverID: serverA, orderedIDs: [1])
    try await database.replaceQueryOrder(queryKey: key("b"), serverID: serverB, orderedIDs: [1])

    #expect(try await database.cachedQueries(serverID: serverA).map(\.key.rawValue) == ["a"])
  }

  // MARK: - QueryRetention (pure)

  @Test("LRU keeps the most recently filled keys, up to the cap")
  func lruKeepsMostRecent() {
    let candidates = [
      CachedQuery(key: key("old"), filledAt: date(1000)),
      CachedQuery(key: key("newest"), filledAt: date(3000)),
      CachedQuery(key: key("middle"), filledAt: date(2000)),
    ]

    #expect(
      QueryRetention.mostRecentlyFilled(candidates, limit: 2)
        == [key("newest"), key("middle")])
    #expect(QueryRetention.mostRecentlyFilled(candidates, limit: 0).isEmpty)
    #expect(QueryRetention.mostRecentlyFilled(candidates, limit: 10).count == 3)
  }

  @Test("LRU ignores keys no fill ever completed")
  func lruIgnoresNeverFilled() {
    let candidates = [
      CachedQuery(key: key("never"), filledAt: nil),
      CachedQuery(key: key("filled"), filledAt: date(1000)),
    ]

    #expect(QueryRetention.mostRecentlyFilled(candidates, limit: 2) == [key("filled")])
  }

  @Test("LRU breaks ties deterministically rather than on iteration order")
  func lruTieBreak() {
    let candidates = [
      CachedQuery(key: key("bbb"), filledAt: date(1000)),
      CachedQuery(key: key("aaa"), filledAt: date(1000)),
    ]

    #expect(QueryRetention.mostRecentlyFilled(candidates, limit: 1) == [key("aaa")])
    #expect(QueryRetention.mostRecentlyFilled(candidates.reversed(), limit: 1) == [key("aaa")])
  }
}
