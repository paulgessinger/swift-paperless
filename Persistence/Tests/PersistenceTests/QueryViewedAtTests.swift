import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// `query_meta.viewed_at` (#678): when a list was last on screen, kept apart from
/// the fill bookkeeping that shares its row.
@Suite("QueryViewedAt")
struct QueryViewedAtTests {
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt) -> Document {
    Document(id: id, title: "d\(id)", created: date(1000), tags: [], owner: .user(1))
  }

  private let list = QueryKey(sentinel: "list")

  @Test("a list viewed before anything was cached for it still gets a stamp")
  func stampsUncachedList() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(1000))

    #expect(try await database.queryViewedAt(queryKey: list, serverID: server) == date(1000))
    // The stamp alone must not read as a list the server says is empty.
    let status = try await database.queryStatus(queryKey: list, serverID: server)
    #expect(status.totalCount == nil)
    #expect(status.localCount == 0)
  }

  @Test("viewing a list again moves its stamp forward")
  func restamps() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(1000))
    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(2000))

    #expect(try await database.queryViewedAt(queryKey: list, serverID: server) == date(2000))
  }

  @Test("fill, rewrite and truncate writes leave the stamp alone")
  func fillWritesKeepStamp() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(1000))

    // A whole fill: page 1 replaces the order and clears `filled_at`, page 2
    // appends, the end stamps completion.
    try await database.writeQueryPage(
      queryKey: list, serverID: server, documents: (1...2).map(doc),
      startPosition: 0, totalCount: 4, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: list, serverID: server, documents: (3...4).map(doc),
      startPosition: 2, totalCount: 4, replaceAll: false)
    try await database.markQueryFillComplete(queryKey: list, serverID: server)
    try await database.replaceQueryOrder(queryKey: list, serverID: server, orderedIDs: [4, 3, 2, 1])
    try await database.truncateQueryOrder(serverID: server, queryKey: list, keepingFirst: 1)

    #expect(try await database.queryViewedAt(queryKey: list, serverID: server) == date(1000))
    #expect(try await database.queryStatus(queryKey: list, serverID: server).totalCount == 4)
  }

  @Test("stamping leaves the fill bookkeeping alone")
  func stampKeepsFillBookkeeping() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.writeQueryPage(
      queryKey: list, serverID: server, documents: (1...2).map(doc),
      startPosition: 0, totalCount: 2, replaceAll: true)
    try await database.markQueryFillComplete(queryKey: list, serverID: server)
    let filledAt = try #require(
      try await database.queryFillCompletedAt(queryKey: list, serverID: server))

    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(1000))

    #expect(try await database.queryStatus(queryKey: list, serverID: server).totalCount == 2)
    #expect(try await database.queryFillCompletedAt(queryKey: list, serverID: server) == filledAt)
  }

  @Test("collecting a list takes its stamp with it")
  func collectionDropsStamp() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.markQueryViewed(queryKey: list, serverID: server, at: date(1000))

    try await database.pruneQueries(serverID: server, collectedKeys: [list])

    #expect(try await database.queryViewedAt(queryKey: list, serverID: server) == nil)
  }
}
