import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The *Recently browsed* cache cap (#678): lists nobody has viewed in a while
/// settle back down to the cap, instead of the cap holding only until the next
/// list open after a downgrade.
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

  /// Cache `ids` as `key`'s full membership, last viewed at `viewedAt` (never,
  /// if `nil`).
  private func cacheList(
    _ key: QueryKey, ids: ClosedRange<UInt>, viewedAt: Date?, server: UUID,
    on database: Persistence.Database
  ) async throws {
    try await database.upsertDocuments(ids.map(doc), serverID: server)
    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: Array(ids))
    if let viewedAt {
      try await database.markQueryViewed(queryKey: key, serverID: server, at: viewedAt)
    }
  }

  private func ids(
    _ key: QueryKey, _ server: UUID, _ database: Persistence.Database
  ) async throws -> [UInt] {
    try await database.queryDocuments(queryKey: key, serverID: server, limit: 1000).map(\.id)
  }

  // MARK: - Settling back to the cap

  @Test("a list not viewed recently settles back to the cap, and its freed documents go")
  func settlesBackToCap() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("list")
    try await cacheList(list, ids: 1...10, viewedAt: date(1000), server: server, on: database)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 3, notViewedSince: cutoff)

    #expect(result == RecentlyBrowsedCapResult(truncatedRows: 7, removedDocuments: 7))
    #expect(try await ids(list, server, database) == [1, 2, 3])
    #expect(try await database.documentCount(serverID: server) == 3)
    // The count pill keeps the server's total, and the list keeps its stamp.
    #expect(try await database.queryStatus(queryKey: list, serverID: server).totalCount == 10)
    #expect(try await database.queryViewedAt(queryKey: list, serverID: server) == date(1000))
  }

  @Test("a list that grew back after the last pass is capped again")
  func recursAfterRegrowth() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("list")
    try await cacheList(list, ids: 1...10, viewedAt: date(1000), server: server, on: database)
    try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 3, notViewedSince: cutoff)

    // A later list open eager-fills the whole thing again.
    try await cacheList(list, ids: 1...10, viewedAt: date(2000), server: server, on: database)
    #expect(try await database.documentCount(serverID: server) == 10)

    try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 3, notViewedSince: cutoff)

    #expect(try await ids(list, server, database) == [1, 2, 3])
    #expect(try await database.documentCount(serverID: server) == 3)
  }

  @Test("a document still listed by another cached list survives its tail being cut")
  func keepsDocumentsListedElsewhere() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("list")
    let other = key("saved-view")
    try await cacheList(list, ids: 1...5, viewedAt: date(1000), server: server, on: database)
    try await cacheList(other, ids: 5...5, viewedAt: date(200_000), server: server, on: database)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 2, notViewedSince: cutoff)

    #expect(result.removedDocuments == 2)
    #expect(try await database.document(serverID: server, id: 5) != nil)
    #expect(try await database.document(serverID: server, id: 4) == nil)
  }

  @Test("steady state: nothing over the cap truncates nothing and scans for no orphans")
  func noPruneWhenNothingTruncated() async throws {
    let server = UUID()
    let database = try database(server)
    let list = key("list")
    try await cacheList(list, ids: 1...3, viewedAt: date(1000), server: server, on: database)
    // Cached by something other than a list (an ASN lookup, say). The prune is
    // tied to having freed something, so this is left for a pass that does.
    try await database.upsertDocuments([doc(99)], serverID: server)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 3, notViewedSince: cutoff)

    #expect(result == RecentlyBrowsedCapResult())
    #expect(try await database.document(serverID: server, id: 99) != nil)
  }

  // MARK: - What it must not touch

  @Test("an Entire library server is left alone")
  func skipsEntireLibraryServer() async throws {
    let server = UUID()
    let database = try database(server, mode: "entireLibrary")
    let list = key("list")
    try await cacheList(list, ids: 1...10, viewedAt: date(1000), server: server, on: database)

    let result = try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 3, notViewedSince: cutoff)

    #expect(result == RecentlyBrowsedCapResult())
    #expect(try await ids(list, server, database).count == 10)
    #expect(try await database.documentCount(serverID: server) == 10)
  }

  @Test("a list viewed at or after the cutoff is kept whole; one never viewed is not")
  func keepsRecentlyViewedLists() async throws {
    let server = UUID()
    let database = try database(server)
    let recent = key("recent")
    let atCutoff = key("at-cutoff")
    let stale = key("stale")
    let neverViewed = key("never-viewed")
    try await cacheList(recent, ids: 1...5, viewedAt: date(200_000), server: server, on: database)
    try await cacheList(atCutoff, ids: 11...15, viewedAt: cutoff, server: server, on: database)
    try await cacheList(stale, ids: 21...25, viewedAt: date(1000), server: server, on: database)
    try await cacheList(neverViewed, ids: 31...35, viewedAt: nil, server: server, on: database)

    try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 2, notViewedSince: cutoff)

    #expect(try await ids(recent, server, database).count == 5)
    #expect(try await ids(atCutoff, server, database).count == 5)
    #expect(try await ids(stale, server, database) == [21, 22])
    #expect(try await ids(neverViewed, server, database) == [31, 32])
  }

  @Test("an exempt list is kept whole however long ago it was viewed")
  func leavesExemptListsAlone() async throws {
    let server = UUID()
    let database = try database(server)
    let exempt = key("default")
    let other = key("other")
    try await cacheList(exempt, ids: 1...5, viewedAt: date(1000), server: server, on: database)
    try await cacheList(other, ids: 11...15, viewedAt: date(1000), server: server, on: database)

    try await database.capRecentlyBrowsedQueries(
      serverID: server, keepingFirst: 2, notViewedSince: cutoff, exempting: [exempt])

    #expect(try await ids(exempt, server, database).count == 5)
    #expect(try await ids(other, server, database) == [11, 12])
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
    let list = key("list")
    try await cacheList(list, ids: 1...5, viewedAt: date(1000), server: serverA, on: database)
    try await cacheList(list, ids: 1...5, viewedAt: date(1000), server: serverB, on: database)

    try await database.capRecentlyBrowsedQueries(
      serverID: serverA, keepingFirst: 2, notViewedSince: cutoff)

    #expect(try await ids(list, serverA, database) == [1, 2])
    #expect(try await ids(list, serverB, database).count == 5)
    #expect(try await database.documentCount(serverID: serverB) == 5)
  }
}
