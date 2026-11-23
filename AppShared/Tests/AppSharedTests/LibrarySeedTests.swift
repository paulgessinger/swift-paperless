import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct LibrarySeedTests {
  private actor Counter {
    private(set) var fetches = 0
    func record(_ name: String) { if name == "fetch" { fetches += 1 } }
  }

  /// Holds every fetch until released.
  private actor Gate {
    private(set) var entered = false
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass(_ name: String) async {
      guard name == "fetch", !isOpen else { return }
      entered = true
      await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
      isOpen = true
      waiters.forEach { $0.resume() }
      waiters = []
    }
  }

  @Test("A running seed counts as syncing, and cancelling the session's work stops it")
  func seedIsBusyAndCancellable() async throws {
    let harness = try await StoreHarness.make()
    _ = try await harness.transient.update(document: document(1))
    let gate = Gate()
    harness.transient.onRequest = { name in await gate.pass(name) }
    let stored = StoredConnection(
      id: harness.serverID, url: URL(string: "https://paperless.example.com/api/")!,
      extraHeaders: [], user: StoreHarness.user)
    _ = try await harness.session.prepareRepository(for: stored)

    let seed = Task { await harness.session.seedLibrary() }
    for _ in 0..<200 where await !gate.entered {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await gate.entered)
    #expect(harness.session.isSyncing)

    harness.session.cancelWork()
    await gate.release()

    #expect(await seed.value == false)
    #expect(!harness.session.isSyncing)
  }

  @Test("The seed pages every document into a Recently browsed server once")
  func seedsOnce() async throws {
    let harness = try await StoreHarness.make()
    for id: UInt in 1...3 {
      _ = try await harness.transient.update(document: document(id))
    }
    let counter = Counter()
    harness.transient.onRequest = { name in await counter.record(name) }
    let stored = StoredConnection(
      id: harness.serverID, url: URL(string: "https://paperless.example.com/api/")!,
      extraHeaders: [], user: StoreHarness.user)
    #expect(
      try harness.database.connection(id: harness.serverID)?.offlineBrowsingMode
        == OfflineBrowsingMode.recentlyBrowsed.rawValue)

    await harness.session.sync(stored: stored, phases: [.seed])

    #expect(try await harness.database.allDocumentIDs(serverID: harness.serverID) == [1, 2, 3])
    #expect(harness.session.syncFailures.isEmpty)
    let afterSeed = await counter.fetches
    #expect(afterSeed > 0)

    await harness.session.sync(stored: stored, phases: [.seed])

    #expect(await counter.fetches == afterSeed)
  }
}
