import Common
import DataModel
import Foundation
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

  @Test("Moving a kept view changes its key; a view that is not kept stays unkept")
  func move() async throws {
    let database = try Database.seeded(serverID: server)
    let moved = QueryKey(sentinel: "moved")
    try await database.keepOfflineView(
      serverID: server, savedViewID: 1, queryKey: QueryKey(sentinel: "old"))

    try await database.moveKeptOfflineView(serverID: server, savedViewID: 1, to: moved)
    try await database.moveKeptOfflineView(serverID: server, savedViewID: 2, to: moved)

    let kept = try await database.keptOfflineViews(serverID: server)
    #expect(kept.map(\.savedViewID) == [1])
    #expect(kept.first?.queryKey == moved)
  }

  // MARK: - Protections

  private let viewKey = QueryKey(sentinel: "view")

  /// A view listing `members`, kept.
  private func keepView(_ database: Database, members: [UInt], id: UInt = 1) async throws {
    try await database.replaceQueryOrder(
      queryKey: viewKey, serverID: server, orderedIDs: members, basis: .initial)
    try await database.keepOfflineView(serverID: server, savedViewID: id, queryKey: viewKey)
  }

  private func recordArchive(
    _ database: Database, _ id: UInt, size: Int64 = 10, modified: Date? = nil
  ) async throws {
    try await database.recordFile(
      FileFixtures.key(server, id), documentID: id, size: size,
      modified: modified ?? date(500), checksum: nil, storedAt: date(1000),
      lastAccessedAt: date(1000))
  }

  @Test("A kept view's members are not evictable until the view is released, unless kept alone")
  func viewMembersAreNotEvictable() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    for id: UInt in [1, 2, 3] { try await recordArchive(database, id) }
    try await keepView(database, members: [1, 2])
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true)

    #expect(try await database.evictableFileBytes() == 10)
    #expect(try await database.archiveFiles(serverID: server).map(\.documentId) == [3])

    try await database.releaseOfflineView(serverID: server, savedViewID: 1)

    #expect(try await database.evictableFileBytes() == 20)
    #expect(
      Set(try await database.archiveFiles(serverID: server).map(\.documentId)) == [1, 3])
  }

  @Test("A document is kept on its own or by a kept view that lists it")
  func isKept() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    try await keepView(database, members: [2])
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true)

    #expect(try await database.isKept(serverID: server, documentID: 1))
    #expect(try await database.isKept(serverID: server, documentID: 2))
    #expect(try await !database.isKept(serverID: server, documentID: 3))
    #expect(try await !database.isKept(serverID: UUID(), documentID: 2))
  }

  @Test("A view's list protects nothing until the view is kept")
  func unkeptViewProtectsNothing() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try await recordArchive(database, 1)
    try await database.replaceQueryOrder(
      queryKey: viewKey, serverID: server, orderedIDs: [1], basis: .initial)

    #expect(try await database.evictableFileBytes() == 10)
  }

  @Test("The kept scope downloads and counts a view's members, a document kept twice once")
  func keptScopeIncludesViewMembers() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    // 1: by the view and alone, fresh. 2: by the view, missing. 3: neither.
    // 9: by the view, no row yet.
    try await recordArchive(database, 1, size: 7)
    try await keepView(database, members: [1, 2, 9])
    try await database.setKeptOffline(serverID: server, documentID: 1, kept: true)

    let needing = try await database.documentsNeedingFiles(
      serverID: server, scope: .keptOffline, excluding: [], limit: 10
    ).filter { $0.kinds.contains(.archive) }.map(\.documentID)
    #expect(needing == [2])

    let progress = try await database.libraryFileProgress(serverID: server, scope: .keptOffline)
    #expect(
      progress == LibraryFileProgress(totalDocuments: 3, downloadedFiles: 1, downloadedBytes: 7))
    let perView = try await database.keptOfflineViewProgress(serverID: server)
    #expect(
      perView == [1: LibraryFileProgress(totalDocuments: 3, downloadedFiles: 1, downloadedBytes: 7)]
    )
  }

  @Test("A kept view never synced counts no members")
  func unsyncedViewProgress() async throws {
    let database = try Database.seeded(serverID: server)
    try await database.keepOfflineView(serverID: server, savedViewID: 4, queryKey: viewKey)

    #expect(try await database.keptOfflineViewProgress(serverID: server) == [4: .zero])
  }
}
