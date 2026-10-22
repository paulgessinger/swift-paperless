import Common
import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The *Kept offline* membership: what it survives, and the local list it is
/// served as.
@Suite("Kept offline")
struct KeptOfflineTests {
  private let server = UUID()
  private func date(_ t: TimeInterval) -> Date { FileFixtures.date(t) }
  private func doc(_ id: UInt) -> Document { FileFixtures.doc(id, modified: date(500)) }

  @Test("Keeping is idempotent and releasing removes the row")
  func setAndRelease() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])

    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true, at: date(1))
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true, at: date(2))
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true, at: date(3))
    #expect(try await database.keptOfflineIDs(serverID: server) == [1, 2])
    #expect(try await database.isKeptOffline(serverID: server, documentID: 1))

    try await database.setKeptOffline(serverID: server, documentID: 1, kept: false)
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: false)
    #expect(try await database.keptOfflineIDs(serverID: server) == [2])
    #expect(try await !database.isKeptOffline(serverID: server, documentID: 1))
  }

  @Test("The membership is configuration: a cache wipe keeps it, removing the server drops it")
  func survivesWipeNotServerRemoval() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true)

    try await database.clearCache()
    #expect(try await database.keptOfflineIDs(serverID: server) == [1])
    // The row is gone with the cache, so the member is missing until a sync.
    #expect(try await database.keptOfflineIDsMissingRows(serverID: server) == [1])

    #expect(try database.deleteConnection(id: server))
    #expect(try await database.keptOfflineIDs(serverID: server).isEmpty)
  }

  @Test("A document deleted on the server leaves the membership")
  func remoteDeleteReleases() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true)
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true)

    try await database.deleteDocuments(serverID: server, removedIDs: [1])

    #expect(try await database.keptOfflineIDs(serverID: server) == [2])
  }

  @Test("The list is served newest membership first, with skeletons for uncached members")
  func listAndStatus() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true, at: date(1))
    try await database.setKeptOffline(serverID: server, documentID: 7, kept: true, at: date(2))
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true, at: date(3))

    let entries = try await database.queryDocuments(
      queryKey: .keptOffline, serverID: server, limit: 10)
    #expect(entries.map(\.id) == [2, 7, 1])
    #expect(entries[1] == .skeleton(id: 7))
    #expect(try await database.keptOfflineIDsMissingRows(serverID: server) == [7])

    let window = try await database.queryDocuments(
      queryKey: .keptOffline, serverID: server, limit: 1, offset: 1)
    #expect(window.map(\.id) == [7])

    let status = try await database.queryStatus(queryKey: .keptOffline, serverID: server)
    #expect(status.totalCount == 3)
    #expect(status.localCount == 2)
    #expect(status.isComplete)
    #expect(!status.orderStale)

    // An ordinary key still replays `query_order`.
    let other = QueryKey(sentinel: "other")
    #expect(try await database.queryDocuments(queryKey: other, serverID: server, limit: 10).isEmpty)
    #expect(try await database.queryStatus(queryKey: other, serverID: server).totalCount == nil)
  }

  @Test("The list observation re-fires on membership and document writes")
  func observation() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    var iterator = database.observeDocumentPrefix(
      queryKey: .keptOffline, serverID: server, limit: 10
    ).makeAsyncIterator()
    #expect(try await iterator.next()?.isEmpty == true)

    try await database.setKeptOffline(serverID: server, documentID: 3, kept: true)
    #expect(try await iterator.next() == [.skeleton(id: 3)])

    try await database.upsertDocuments([doc(3)], serverID: server)
    #expect(try await iterator.next()?.map(\.id) == [3])

    var ids = database.observeKeptOfflineIDs(serverID: server).makeAsyncIterator()
    #expect(try await ids.next() == [3])
    try await database.setKeptOffline(serverID: server, documentID: 3, kept: false)
    #expect(try await ids.next() == [])
  }
}
