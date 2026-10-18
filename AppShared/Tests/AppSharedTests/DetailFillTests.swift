import DataModel
import Foundation
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct DetailFillTests {
  /// The most requests running at once.
  private actor Gauge {
    private var running = 0
    private(set) var peak = 0
    private(set) var count = 0

    func enter() {
      running += 1
      count += 1
      peak = max(peak, running)
    }

    func leave() { running -= 1 }
  }

  @Test("The detail fill keeps a window of metadata requests in flight and fetches every one")
  func fetchesConcurrently() async throws {
    let documents = (1...20).map { id in
      var document = document(UInt(id))
      document.modified = Date(timeIntervalSince1970: 500)
      return document
    }
    let harness = try await StoreHarness.make(documents: documents)
    try harness.database.upsertConnection(
      ConnectionRecord(
        id: harness.serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: "entireLibrary"))
    let gauge = Gauge()
    harness.transient.onRequest = { name in
      guard name == "metadata" else { return }
      await gauge.enter()
      try? await Task.sleep(for: .milliseconds(20))
      await gauge.leave()
    }

    #expect(await harness.session.fillDocumentDetails())

    #expect(await gauge.count == 20)
    #expect(await gauge.peak == DetailFillPolicy.concurrency)
    let missing = try await harness.database.documentIDsNeedingFileMetadataFetch(
      serverID: harness.serverID)
    #expect(missing.isEmpty)
  }
}
