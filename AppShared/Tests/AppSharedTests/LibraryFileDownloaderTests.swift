import Common
import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

/// The window of library file downloads: what is queued, how a finished
/// task is filed, and what stops the queueing.
@Suite(.serialized)
@MainActor
struct LibraryFileDownloaderTests {
  private let server = UUID()

  private func doc(_ id: UInt) -> Document {
    Document(
      id: id, title: "d\(id)", created: Date(timeIntervalSince1970: 1000), tags: [],
      modified: Date(timeIntervalSince1970: 500), owner: .user(1))
  }

  private struct Fixture {
    let database: Database
    let store: ContentStore
    let reclaimer: ContentReclaimer
    let downloader: LibraryFileDownloader
    var failures: Failures
  }

  @MainActor
  final class Failures {
    var errors: [(UUID, any Error)] = []
  }

  private func makeFixture(
    documents: [UInt], isEntireLibrary: Bool = true, syncOverCellular: Bool = false,
    freeSpace: Int64 = 10_000_000_000, window: Int = 3
  ) throws -> Fixture {
    let database = try Database.seeded(serverID: server, documents: documents.map(doc))
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("LibraryFileDownloaderTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = try ContentStore(root: root)
    let reclaimer = ContentReclaimer(database: database, store: store)
    let repository = TransientRepository()
    let serverID = server
    let failures = Failures()
    let downloader = LibraryFileDownloader(
      database: database, store: store, index: reclaimer,
      suspension: DatabaseSuspensionController(),
      servers: { id in
        id == serverID
          ? LibraryDownloadServer(
            repository: repository, syncOverCellular: syncOverCellular,
            isEntireLibrary: isEntireLibrary)
          : nil
      },
      allServerIDs: { [serverID] },
      identityName: { _ in nil },
      availableCapacity: { _ in freeSpace },
      window: window,
      makeSession: StubDownloadURLProtocol.makeSession)
    downloader.onFailure = { id, error in failures.errors.append((id, error)) }
    return Fixture(
      database: database, store: store, reclaimer: reclaimer, downloader: downloader,
      failures: failures)
  }

  private func key(_ version: UInt) -> ContentStore.Key {
    ContentStore.Key(serverID: server, versionID: version, kind: .archive)
  }

  private func waitUntil(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @MainActor () async throws -> Bool
  ) async throws {
    for _ in 0..<500 where try await !condition() {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await condition(), sourceLocation: sourceLocation)
  }

  @Test("Queues up to the window, newest document first, with the server's network policy")
  func queuesTheWindow() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let fixture = try makeFixture(documents: [1, 2, 3, 4, 5], syncOverCellular: true)

    let outcome = try await fixture.downloader.refill(serverID: server)

    #expect(outcome == .queued(3))
    #expect(fixture.downloader.inFlight[server] == 3)
    try await waitUntil { StubDownloadURLProtocol.requests.count == 3 }
    let paths = StubDownloadURLProtocol.requests.compactMap(\.url?.path)
    #expect(
      Set(paths) == ["/documents/5/download", "/documents/4/download", "/documents/3/download"])
    let request = try #require(StubDownloadURLProtocol.requests.first)
    #expect(request.allowsExpensiveNetworkAccess)
    #expect(!request.allowsConstrainedNetworkAccess)

    // The in-flight tasks are skipped, and the window is full.
    #expect(try await fixture.downloader.refill(serverID: server) == .queued(0))
    #expect(fixture.downloader.inFlight[server] == 3)
    await fixture.downloader.invalidate()
  }

  @Test("A finished download lands in the store with its row, and the window refills")
  func storesAndRefills() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { request in
      request.url?.path.contains("/documents/2/") == true ? nil : (200, Data("PDF".utf8))
    }
    let fixture = try makeFixture(documents: [1, 2, 3], window: 1)

    #expect(try await fixture.downloader.refill(serverID: server) == .queued(1))

    // 3 finishes and is filed; the refill queues 2, which never finishes.
    try await waitUntil { fixture.store.exists(self.key(3)) }
    try await waitUntil {
      try await fixture.database.libraryFileProgress(serverID: self.server).downloadedFiles == 1
    }
    let progress = try await fixture.database.libraryFileProgress(serverID: server)
    #expect(
      progress
        == LibraryFileProgress(
          totalDocuments: 3, downloadedFiles: 1,
          downloadedBytes: try #require(fixture.store.size(of: key(3)))))
    #expect(try await fixture.reclaimer.isFresh(key(3), modified: doc(3).modified!))
    try await waitUntil { StubDownloadURLProtocol.requests.count == 2 }
    #expect(StubDownloadURLProtocol.requests.last?.url?.path == "/documents/2/download")
    try await waitUntil { fixture.downloader.inFlight[self.server] == 1 }
    #expect(fixture.downloader.activities[server]?.stage == .fileDownload)
    #expect(fixture.downloader.activities[server]?.completed == 1)
    #expect(fixture.downloader.activities[server]?.total == 3)
    #expect(fixture.failures.errors.isEmpty)
    await fixture.downloader.invalidate()
  }

  @Test("A failed download is reported, not stored, and left alone for a while")
  func failureIsReported() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in (403, Data()) }
    let fixture = try makeFixture(documents: [1], window: 2)

    #expect(try await fixture.downloader.refill(serverID: server) == .queued(1))

    try await waitUntil { fixture.failures.errors.count == 1 }
    #expect(fixture.failures.errors.first?.0 == server)
    #expect(fixture.failures.errors.first?.1 is RequestError)
    #expect(!fixture.store.exists(key(1)))
    try await waitUntil { fixture.downloader.inFlight[self.server] == 0 }
    // The refill after the failure does not queue it again.
    #expect(StubDownloadURLProtocol.requests.count == 1)
    #expect(try await fixture.downloader.refill(serverID: server) == .complete)
    #expect(fixture.downloader.activities[server] == nil)
    await fixture.downloader.invalidate()
  }

  @Test("Low free space pauses the queueing until space is back")
  func lowStoragePauses() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let fixture = try makeFixture(documents: [1], freeSpace: 1)

    #expect(try await fixture.downloader.refill(serverID: server) == .pausedLowStorage)
    #expect(fixture.downloader.pausedLowStorage)
    #expect(StubDownloadURLProtocol.requests.isEmpty)

    let roomy = try makeFixture(documents: [1])
    #expect(try await roomy.downloader.refill(serverID: server) == .queued(1))
    #expect(!roomy.downloader.pausedLowStorage)
    await fixture.downloader.invalidate()
    await roomy.downloader.invalidate()
  }

  @Test("A server outside Entire library, or unknown, queues nothing")
  func onlyLibraryServers() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let fixture = try makeFixture(documents: [1], isEntireLibrary: false)

    #expect(try await fixture.downloader.refill(serverID: server) == .complete)
    #expect(try await fixture.downloader.refill(serverID: UUID()) == .complete)
    #expect(StubDownloadURLProtocol.requests.isEmpty)
    await fixture.downloader.invalidate()
  }

  @Test("Cancelling a server calls off its tasks only")
  func cancelIsScoped() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let fixture = try makeFixture(documents: [1, 2], window: 2)
    #expect(try await fixture.downloader.refill(serverID: server) == .queued(2))

    await fixture.downloader.cancel(serverID: UUID())
    #expect(try await fixture.downloader.refill(serverID: server) == .queued(0))
    await fixture.downloader.cancel(serverID: server)
    #expect(fixture.downloader.inFlight[server] == nil)
    // The cancellations complete the tasks, and the server is still in
    // Entire library, so the refill behind them queues the files again.
    try await waitUntil { StubDownloadURLProtocol.requests.count == 4 }
    try await waitUntil { fixture.downloader.inFlight[self.server] == 2 }
    await fixture.downloader.invalidate()
  }

  @Test("The background events completion runs once the completions' refills are done")
  func backgroundEventsCompletion() async throws {
    let lease = await StubDownloadURLProtocol.lease()
    defer { lease.release() }
    StubDownloadURLProtocol.responder = { _ in nil }
    let fixture = try makeFixture(documents: [1])
    let called = Failures()
    fixture.downloader.backgroundEventsCompletion = {
      called.errors.append((UUID(), CancellationError()))
    }

    await fixture.downloader.backgroundEventsDidFinish()

    #expect(called.errors.count == 1)
    #expect(fixture.downloader.backgroundEventsCompletion == nil)
    await fixture.downloader.invalidate()
  }
}
