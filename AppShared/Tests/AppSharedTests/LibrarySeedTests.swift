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
