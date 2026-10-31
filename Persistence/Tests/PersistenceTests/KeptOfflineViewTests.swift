import Common
import DataModel
import Foundation
import Testing

@testable import Persistence

/// The kept saved views and the members they keep: what they survive, how
/// they overlap with documents kept on their own, and their figures.
@Suite("Kept offline views")
struct KeptOfflineViewTests {
  private let server = UUID()
  private func date(_ t: TimeInterval) -> Date { FileFixtures.date(t) }
  private func doc(_ id: UInt) -> Document { FileFixtures.doc(id, modified: date(500)) }

  /// A kept view with `members`.
  private func keepView(_ database: Database, members: [UInt], id: UInt = 1) async throws {
    try await database.keepOfflineView(serverID: server, savedViewID: id)
    try await database.replaceKeptOfflineViewMembers(
      serverID: server, savedViewID: id, documentIDs: members)
  }

  private func recordArchive(_ database: Database, _ id: UInt, size: Int64 = 10) async throws {
    try await database.recordFile(
      FileFixtures.key(server, id), documentID: id, size: size, modified: date(500),
      checksum: nil, storedAt: date(1000), lastAccessedAt: date(1000))
  }

  @Test("Keeping is idempotent, newest first, and releasing drops the view and its members")
  func keepAndRelease() async throws {
    let database = try Database.seeded(serverID: server)
    try await database.keepOfflineView(serverID: server, savedViewID: 1, at: date(1))
    try await database.keepOfflineView(serverID: server, savedViewID: 2, at: date(2))
    try await database.keepOfflineView(serverID: server, savedViewID: 1, at: date(3))
    #expect(
      try await database.keptOfflineViews(serverID: server).map(\.savedViewID) == [1, 2])
    try await database.replaceKeptOfflineViewMembers(
      serverID: server, savedViewID: 1, documentIDs: [5])

    try await database.releaseOfflineView(serverID: server, savedViewID: 1)
    try await database.releaseOfflineView(serverID: server, savedViewID: 1)

    #expect(try await database.keptOfflineViews(serverID: server).map(\.savedViewID) == [2])
    #expect(try await !database.isKept(serverID: server, documentID: 5))
  }

  @Test("Replacing members reports who joined, and writes nothing for a view not kept")
  func replaceMembers() async throws {
    let database = try Database.seeded(serverID: server)
    try await database.keepOfflineView(serverID: server, savedViewID: 1)

    #expect(
      try await database.replaceKeptOfflineViewMembers(
        serverID: server, savedViewID: 1, documentIDs: [1, 2]) == 2)
    #expect(
      try await database.replaceKeptOfflineViewMembers(
        serverID: server, savedViewID: 1, documentIDs: [2, 3]) == 1)
    #expect(try await !database.isKept(serverID: server, documentID: 1))
    #expect(try await database.isKept(serverID: server, documentID: 3))

    #expect(
      try await database.replaceKeptOfflineViewMembers(
        serverID: server, savedViewID: 9, documentIDs: [4]) == 0)
    #expect(try await !database.isKept(serverID: server, documentID: 4))
  }

  @Test(
    "Views and members are configuration: a cache wipe keeps them, removing the server drops them")
  func survivesWipeNotServerRemoval() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    try await keepView(database, members: [1])

    try await database.clearCache()
    #expect(try await database.keptOfflineViews(serverID: server).count == 1)
    #expect(try await database.isKept(serverID: server, documentID: 1))
    // The row is gone with the cache, so the member is fetched again.
    #expect(try await database.keptOfflineIDsMissingRows(serverID: server) == [1])

    #expect(try database.deleteConnection(id: server))
    #expect(try await database.keptOfflineViews(serverID: server).isEmpty)
    #expect(try await !database.isKept(serverID: server, documentID: 1))
  }

  @Test("A view the server no longer has is released with its members")
  func releaseDeleted() async throws {
    let database = try Database.seeded(serverID: server)
    try await keepView(database, members: [1], id: 1)
    try await keepView(database, members: [2], id: 2)

    let released = try await database.releaseDeletedOfflineViews(
      serverID: server, existing: [1, 3])

    #expect(released == [2])
    #expect(try await database.keptOfflineViews(serverID: server).map(\.savedViewID) == [1])
    #expect(try await !database.isKept(serverID: server, documentID: 2))
  }

  @Test("A view's members are kept, but neither listed nor toggled as kept on their own")
  func membersAreNotOwnMembership() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    try await keepView(database, members: [1, 2])
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true)

    #expect(try await database.keptOfflineIDs(serverID: server) == [2])
    #expect(try await !database.isKeptOffline(serverID: server, documentID: 1))
    let listed = try await database.queryDocuments(
      queryKey: .keptOffline, serverID: server, limit: 10)
    #expect(listed.map(\.id) == [2])

    // Releasing the document on its own leaves it kept by the view.
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: false)
    #expect(try await database.isKept(serverID: server, documentID: 2))
  }

  // MARK: - Protections

  @Test("A kept view's members are not evictable until the view is released, unless kept alone")
  func viewMembersAreNotEvictable() async throws {
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    for id: UInt in [1, 2, 3] { try await recordArchive(database, id) }
    try await keepView(database, members: [1, 2])
    try await database.setKeptOffline(serverID: server, documentID: 2, kept: true)

    #expect(try await database.evictableFileBytes() == 10)
    #expect(try await database.libraryPinnedFiles(serverID: server).map(\.documentId) == [3])

    try await database.releaseOfflineView(serverID: server, savedViewID: 1)

    #expect(try await database.evictableFileBytes() == 20)
    #expect(
      Set(try await database.libraryPinnedFiles(serverID: server).map(\.documentId)) == [1, 3])
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
    try await database.keepOfflineView(serverID: server, savedViewID: 4)

    #expect(try await database.keptOfflineViewProgress(serverID: server) == [4: .zero])
  }
}
