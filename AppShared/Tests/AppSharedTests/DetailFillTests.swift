import DataModel
import Foundation
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct DetailFillTests {
  /// The most requests running at once. Requests wait in `enter` until
  /// `fill` are in flight together, so the window fills on any runner.
  private actor Gauge {
    private let fill: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var peak = 0
    private(set) var count = 0

    init(fill: Int) { self.fill = fill }

    func enter() async {
      running += 1
      count += 1
      peak = max(peak, running)
      guard peak < fill else {
        waiting.forEach { $0.resume() }
        waiting.removeAll()
        return
      }
      await withCheckedContinuation { waiting.append($0) }
    }

    func leave() { running -= 1 }
  }

  @Test(
    "The detail fill keeps a window of metadata requests in flight and fetches every one",
    .timeLimit(.minutes(1)))
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
    let gauge = Gauge(fill: DetailFillPolicy.concurrency)
    harness.transient.onRequest = { name in
      guard name == "metadata" else { return }
      await gauge.enter()
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
