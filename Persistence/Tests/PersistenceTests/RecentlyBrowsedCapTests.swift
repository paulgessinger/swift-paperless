import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The recurring *Recently browsed* cache cap (#678): lists the user browsed in
/// full settle back down to the cap once nobody is using them, instead of the
/// cap holding only until the next list open after a downgrade.
@Suite("RecentlyBrowsedCap")
struct RecentlyBrowsedCapTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt) -> Document {
    Document(id: id, title: "d\(id)", created: date(1000), tags: [], owner: .user(1))
  }

  private func key(_ name: String) -> QueryKey { QueryKey(sentinel: name) }

  /// A "now" well after every stamp the tests write, and the cutoff a 24 h
  /// grace would derive from it.
  private let cutoff = Date(timeIntervalSince1970: 100_000)

  private func database(
    _ server: UUID, mode: String = "recentlyBrowsed"
  ) throws -> Persistence.Database {
    let database = try Database.seeded(serverID: server)
    try database.upsertConnection(
      ConnectionRecord(
        id: server,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: mode))
    return database
  }

  /// Cache `ids` as `key`'s full membership, stamped as completed at `filledAt`.
  private func cacheList(
    _ key: QueryKey, ids: ClosedRange<UInt>, filledAt: Date?, server: UUID,
    on database: Persistence.Database
  ) async throws {
    try await database.upsertDocuments(ids.map(doc), serverID: server)
    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: Array(ids))
    try setFilledAt(filledAt, key: key, serverID: server, on: database)
  }

  /// Non-`async` on purpose: inside an `async` function `writer.write` resolves
  /// to the `async` overload.
  private func setFilledAt(
    _ filledAt: Date?, key: QueryKey, serverID: UUID, on database: Persistence.Database
  ) throws {
    try database.writer.write { db in
      try db.execute(
        sql: "UPDATE query_meta SET filled_at = ? WHERE server_id = ? AND query_key = ?",
        arguments: [filledAt, serverID, key.rawValue])
    }
  }

  private func ids(
    _ key: QueryKey, _ server: UUID, _ database: Persistence.Database
  ) async throws -> [UInt] {
    try await database.queryDocuments(queryKey: key, serverID: server, limit: 1000).map(\.id)
  }

  // MARK: - Settling back to the cap

  @Test("a list browsed in full settles back to the cap, and its freed documents go")
  func settlesBackToCap() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("default")
    try await cacheList(list, ids: 1...10, filledAt: date(1000), server: server, on: database)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [list], keepingFirst: 3, completedBefore: cutoff)

    #expect(result == RecentlyBrowsedCapResult(truncatedRows: 7, removedDocuments: 7))
    #expect(try await ids(list, server, database) == [1, 2, 3])
    #expect(try await database.documentCount(serverID: server) == 3)
    // The count pill keeps the server's total; the LRU keeps its real stamp.
    #expect(try await database.queryStatus(queryKey: list, serverID: server).totalCount == 10)
    #expect(
      try await database.queryFillCompletedAt(queryKey: list, serverID: server) == date(1000))
  }

  @Test("recurring: a list that grew back after the last pass is capped again")
  func recursAfterRegrowth() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("default")
    try await cacheList(list, ids: 1...10, filledAt: date(1000), server: server, on: database)
    try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [list], keepingFirst: 3, completedBefore: cutoff)

    // A later list open eager-fills the whole thing again.
    try await cacheList(list, ids: 1...10, filledAt: date(2000), server: server, on: database)
    #expect(try await database.documentCount(serverID: server) == 10)

    try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [list], keepingFirst: 3, completedBefore: cutoff)

    #expect(try await ids(list, server, database) == [1, 2, 3])
    #expect(try await database.documentCount(serverID: server) == 3)
  }

  @Test("a document still listed by another cached list survives its tail being cut")
  func keepsDocumentsListedElsewhere() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("default")
    let other = key("saved-view")
    try await cacheList(list, ids: 1...5, filledAt: date(1000), server: server, on: database)
    try await database.replaceQueryOrder(queryKey: other, serverID: server, orderedIDs: [5])

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [list], keepingFirst: 2, completedBefore: cutoff)

    #expect(result.removedDocuments == 2)
    #expect(try await database.document(serverID: server, id: 5) != nil)
    #expect(try await database.document(serverID: server, id: 4) == nil)
  }

  @Test("steady state: nothing over the cap truncates nothing and scans for no orphans")
  func noPruneWhenNothingTruncated() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("default")
    try await cacheList(list, ids: 1...3, filledAt: date(1000), server: server, on: database)
    // Cached by something other than a list (an ASN lookup, say). The prune is
    // tied to having freed something, so this is left for a pass that does.
    try await database.upsertDocuments([doc(99)], serverID: server)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [list], keepingFirst: 3, completedBefore: cutoff)

    #expect(result == RecentlyBrowsedCapResult())
    #expect(try await database.document(serverID: server, id: 99) != nil)
  }

  // MARK: - What it must not touch

  @Test("an Entire library server is left alone, whatever the caller asks")
  func skipsEntireLibraryServer() async throws {
    let server = UUID()
    let database = try database(server, mode: "entireLibrary")
    let list = key("default")
    try await cacheList(list, ids: 1...10, filledAt: date(1000), server: server, on: database)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [list], keepingFirst: 3, completedBefore: cutoff)

    #expect(result == RecentlyBrowsedCapResult())
    #expect(try await ids(list, server, database).count == 10)
    #expect(try await database.documentCount(serverID: server) == 10)
  }

  @Test("a list completed at or after the cutoff is kept whole")
  func keepsRecentlyCompletedList() async throws {
    let server = UUID()
    let database = try database(server)
    let recent = key("recent")
    let atCutoff = key("at-cutoff")
    let stale = key("stale")
    let unstamped = key("unstamped")
    try await cacheList(recent, ids: 1...5, filledAt: date(200_000), server: server, on: database)
    try await cacheList(atCutoff, ids: 11...15, filledAt: cutoff, server: server, on: database)
    try await cacheList(stale, ids: 21...25, filledAt: date(1000), server: server, on: database)
    try await cacheList(unstamped, ids: 31...35, filledAt: nil, server: server, on: database)

    // The caller's snapshot may be stale; the accessor re-checks the stamp.
    try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [recent, atCutoff, stale, unstamped], keepingFirst: 2,
      completedBefore: cutoff)

    #expect(try await ids(recent, server, database).count == 5)
    #expect(try await ids(atCutoff, server, database).count == 5)
    #expect(try await ids(stale, server, database) == [21, 22])
    #expect(try await ids(unstamped, server, database) == [31, 32])
  }

  @Test("only the named keys are cut: a list being filled outside the snapshot keeps its pages")
  func onlyTouchesNamedKeys() async throws {
    let server = UUID()
    let database = try database(server)
    let capped = key("capped")
    let filling = key("filling")
    try await cacheList(capped, ids: 1...5, filledAt: date(1000), server: server, on: database)
    // Mid-fill: pages written, no completion stamp yet.
    try await database.writeQueryPage(
      queryKey: filling, serverID: server, documents: (11...15).map(doc),
      startPosition: 0, totalCount: 50, replaceAll: true)

    try await database.capRecentlyBrowsedQueries(
      serverID: server, candidateKeys: [capped], keepingFirst: 2, completedBefore: cutoff)

    #expect(try await ids(capped, server, database) == [1, 2])
    #expect(try await ids(filling, server, database) == [11, 12, 13, 14, 15])
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
    let list = key("default")
    try await cacheList(list, ids: 1...5, filledAt: date(1000), server: serverA, on: database)
    try await cacheList(list, ids: 1...5, filledAt: date(1000), server: serverB, on: database)

    try await database.capRecentlyBrowsedQueries(
      serverID: serverA, candidateKeys: [list], keepingFirst: 2, completedBefore: cutoff)

    #expect(try await ids(list, serverA, database) == [1, 2])
    #expect(try await ids(list, serverB, database).count == 5)
    #expect(try await database.documentCount(serverID: serverB) == 5)
  }

  // MARK: - Candidate policy (pure)

  @Test("candidates exclude pinned keys and lists completed since the cutoff")
  func candidatePolicy() {
    let cached = [
      CachedQuery(key: key("stale"), filledAt: date(1000)),
      CachedQuery(key: key("unstamped"), filledAt: nil),
      CachedQuery(key: key("recent"), filledAt: date(200_000)),
      CachedQuery(key: key("at-cutoff"), filledAt: cutoff),
      CachedQuery(key: key("in-flight"), filledAt: nil),
      CachedQuery(key: key("on-screen"), filledAt: date(1000)),
    ]

    let candidates = QueryRetention.recentlyBrowsedCapCandidates(
      cached, pinned: [key("in-flight"), key("on-screen")], completedBefore: cutoff)

    #expect(candidates == [key("stale"), key("unstamped")])
  }
}
