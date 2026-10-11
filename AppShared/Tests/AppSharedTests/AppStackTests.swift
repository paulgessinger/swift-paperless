import Common
import DataModel
import Foundation
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct AppStackTests {
  @Test("The connection manager reads the servers from the stack's database")
  func connectionManagerSharesDatabase() throws {
    let serverID = UUID()
    let stack = AppStack(database: try Database.seeded(serverID: serverID))

    #expect(stack.connectionManager.connections.keys.contains(serverID))
  }

  @Test("The registry hands out one session per server")
  func oneSessionPerServer() throws {
    let serverID = UUID()
    let stack = AppStack(database: try Database.seeded(serverID: serverID))

    let first = stack.sessionRegistry.session(for: serverID)
    #expect(stack.sessionRegistry.session(for: serverID) === first)
    #expect(stack.sessionRegistry.session(for: UUID()) !== first)
  }

  @Test("The registry reports a removed server, for the files that live outside the database")
  func serverRemovalIsReported() async throws {
    let serverID = UUID()
    let stack = AppStack(database: try Database.seeded(serverID: serverID))
    var removed: Set<UUID> = []
    stack.sessionRegistry.onServersRemoved = { removed = $0 }
    stack.sessionRegistry.start()

    _ = try stack.database.deleteConnection(id: serverID)

    try await waitUntil({ removed == [serverID] }, "the removal was never reported")
  }

  @Test("Only a stack asked to builds the file downloader, and hands it to the registry")
  func fileDownloaderIsOptIn() async throws {
    let serverID = UUID()
    let plain = AppStack(database: try Database.seeded(serverID: serverID))
    #expect(plain.fileDownloader == nil)

    let store = try makeStore()
    let stack = AppStack(
      database: try Database.seeded(serverID: serverID), contentStore: store,
      buildsFileDownloader: true, fileDownloaderSession: StubDownloadURLProtocol.makeSession)
    let downloader = try #require(stack.fileDownloader)
    #expect(stack.sessionRegistry.fileDownloader === downloader)
    #expect(
      AppStack(database: try Database.seeded(), buildsFileDownloader: true).fileDownloader == nil)
    await downloader.invalidate()
  }

  @Test("Leaving Entire library calls the server's downloads off and drops its archives")
  func downgradeDropsArchives() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let serverID = UUID()
    var document = document(1)
    document.modified = Date(timeIntervalSince1970: 500)
    let database = try Database.seeded(serverID: serverID, documents: [document])
    try database.upsertConnection(
      ConnectionRecord(
        id: serverID, url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: "entireLibrary"))
    let store = try makeStore()
    let stack = AppStack(
      database: database, contentStore: store, buildsFileDownloader: true,
      fileDownloaderSession: StubDownloadURLProtocol.makeSession)
    let downloader = try #require(stack.fileDownloader)
    let key = ContentStore.Key(serverID: serverID, versionID: 1, kind: .archive)
    try store.storeData(Data("PDF".utf8), for: key)
    try await stack.contentReclaimer.recordStore(
      key, documentID: 1, size: 3, modified: document.modified, checksum: nil, storedAt: Date())
    stack.connectionManager.setActiveConnection(id: serverID, animated: false)

    stack.connectionManager.setOfflineBrowsingMode(.recentlyBrowsed)

    try await waitUntil({ !store.exists(key) }, "the archive was never removed")
    #expect(try await database.allFileKeys().isEmpty)
    #expect(try await downloader.refill(serverID: serverID) == .complete)
    await downloader.invalidate()
  }

  private func makeStore() throws -> ContentStore {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AppStackTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return try ContentStore(root: root)
  }

  @Test("Without a content store the stack caches no files and the reclaim is harmless")
  func noStoreNoFiles() async throws {
    let stack = AppStack(database: try Database.seeded())

    #expect(stack.sessionRegistry.contentReclaimer?.store == nil)
    let report = await stack.contentReclaimer.run(reason: .manual)
    #expect(report.removedFiles == 0)
    #expect(!report.walked)
  }
}
