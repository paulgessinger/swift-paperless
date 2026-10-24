import Common
import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The kept saved views: what the membership survives, and how it follows the
/// server's saved views.
@Suite("Kept offline views")
struct KeptOfflineViewTests {
  private let server = UUID()
  private func date(_ t: TimeInterval) -> Date { FileFixtures.date(t) }
  private func doc(_ id: UInt) -> Document { FileFixtures.doc(id, modified: date(500)) }

  @Test("Keeping is idempotent, newest first, and releasing removes the row")
  func keepAndRelease() async throws {
    let database = try Database.seeded(serverID: server)
    let a = QueryKey(sentinel: "a")
    let b = QueryKey(sentinel: "b")

    try await database.keepOfflineView(serverID: server, savedViewID: 1, queryKey: a, at: date(1))
    try await database.keepOfflineView(serverID: server, savedViewID: 2, queryKey: b, at: date(2))
    try await database.keepOfflineView(serverID: server, savedViewID: 1, queryKey: a, at: date(3))
    #expect(
      try await database.keptOfflineViews(serverID: server).map(\.savedViewID) == [1, 2])

    try await database.releaseOfflineView(serverID: server, savedViewID: 1)
    try await database.releaseOfflineView(serverID: server, savedViewID: 1)
    #expect(try await database.keptOfflineViews(serverID: server).map(\.savedViewID) == [2])
  }

  @Test("The kept views are configuration: a cache wipe keeps them, removing the server drops them")
  func survivesWipeNotServerRemoval() async throws {
    let database = try Database.seeded(serverID: server)
    try await database.keepOfflineView(
      serverID: server, savedViewID: 1, queryKey: QueryKey(sentinel: "a"))

    try await database.clearCache()
    #expect(try await database.keptOfflineViews(serverID: server).count == 1)

    #expect(try database.deleteConnection(id: server))
    #expect(try await database.keptOfflineViews(serverID: server).isEmpty)
  }

  @Test("Reconciling follows an edited view's key and releases a deleted one")
  func reconcile() async throws {
    let database = try Database.seeded(serverID: server)
    let old = QueryKey(sentinel: "old")
    let moved = QueryKey(sentinel: "moved")
    try await database.keepOfflineView(serverID: server, savedViewID: 1, queryKey: old)
    try await database.keepOfflineView(serverID: server, savedViewID: 2, queryKey: old)

    let released = try await database.reconcileKeptOfflineViews(
      serverID: server, currentKeys: [1: moved, 3: old])

    #expect(released == [2])
    let kept = try await database.keptOfflineViews(serverID: server)
    #expect(kept.map(\.savedViewID) == [1])
    #expect(kept.first?.queryKey == moved)
  }
}
