import Common
import DataModel
import Foundation
import Testing

@testable import Networking

// Serialized: `NetworkTransfer.sink` is a process-wide global, so tests that
// swap it cannot run in parallel with each other.
@Suite("Transfer accounting", .serialized)
struct TransferStatsTest {
  /// Collects what the sink is handed, from whatever thread delivers it.
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(Int, TransferCategory)] = []
    func record(_ bytes: Int, _ category: TransferCategory) {
      lock.withLock { entries.append((bytes, category)) }
    }
    var categories: [TransferCategory] { lock.withLock { entries.map(\.1) } }
    func bytes(in category: TransferCategory) -> [Int] {
      lock.withLock { entries.filter { $0.1 == category }.map(\.0) }
    }
  }

  private func withSink(_ body: (Recorder) throws -> Void) rethrows {
    let recorder = Recorder()
    let previous = NetworkTransfer.sink
    NetworkTransfer.sink = { bytes, category in recorder.record(bytes, category) }
    defer { NetworkTransfer.sink = previous }
    try body(recorder)
  }

  private func withSink(_ body: (Recorder) async throws -> Void) async rethrows {
    let recorder = Recorder()
    let previous = NetworkTransfer.sink
    NetworkTransfer.sink = { bytes, category in recorder.record(bytes, category) }
    defer { NetworkTransfer.sink = previous }
    try await body(recorder)
  }

  @Test("record(bytes:) reads the ambient task-local category")
  func recordUsesTaskLocal() async {
    withSink { recorder in
      NetworkTransfer.$category.withValue(.reconcile) {
        NetworkTransfer.record(bytes: 10)
      }
      #expect(recorder.categories == [.reconcile])
    }
  }

  @Test("record(bytes:category:) uses the category it is handed, not the ambient one")
  func recordUsesExplicitCategory() {
    // The case that matters: bytes counted on a URLSession delegate callback
    // arrive *outside* the task that set the task-local, so the category has to
    // travel as a value. Reading the task-local there silently filed every
    // transfer under `.other`.
    withSink { recorder in
      NetworkTransfer.$category.withValue(.reconcile) {
        NetworkTransfer.record(bytes: 10, category: .fill)
      }
      #expect(recorder.categories == [.fill])
    }
  }

  @Test("a captured category survives being used from another task")
  func capturedCategorySurvivesTaskHop() async {
    let captured: TransferCategory = NetworkTransfer.$category.withValue(.fill) {
      NetworkTransfer.category
    }
    await withSink { recorder in
      // A detached task inherits no task-local — the same shape as a delegate
      // queue callback.
      await Task.detached {
        #expect(NetworkTransfer.category == .other)
        NetworkTransfer.record(bytes: 42, category: captured)
      }.value
      #expect(recorder.categories == [.fill])
    }
  }

  @Test("zero-byte records are dropped")
  func zeroBytesIgnored() {
    withSink { recorder in
      NetworkTransfer.record(bytes: 0, category: .fill)
      #expect(recorder.categories.isEmpty)
    }
  }

  @Test("with no category set, records land in .other")
  func defaultCategoryIsOther() {
    withSink { recorder in
      NetworkTransfer.record(bytes: 10)
      #expect(recorder.categories == [.other])
    }
  }

  @Test("the innermost category wins when scopes nest")
  func innermostCategoryWins() {
    // The shared fill path runs inside the proactive sweep's `.fill` scope as
    // well as on its own, so an inner scope has to override an outer one rather
    // than be swallowed by it.
    withSink { recorder in
      NetworkTransfer.$category.withValue(.fill) {
        NetworkTransfer.record(bytes: 1)
        NetworkTransfer.$category.withValue(.list) {
          NetworkTransfer.record(bytes: 1)
        }
        NetworkTransfer.record(bytes: 1)
      }
      #expect(recorder.categories == [.fill, .list, .fill])
    }
  }

  @Test("the image session delegate files its bytes under thumbnails")
  @MainActor
  func imageSessionDelegateRecordsThumbnails() throws {
    let repository = ApiRepository(
      connection: Connection(
        url: URL(string: "https://example.com")!, token: "t", identityName: nil,
        serverID: UUID()),
      mode: .release, contentStore: nil, urlSession: URLSession(configuration: .ephemeral))
    let delegate = try #require(repository.imageSessionDelegate as? PaperlessURLSessionDelegate)

    withSink { recorder in
      // Wrapped in a different ambient category: the callback runs on a
      // URLSession queue in production, so the category must be fixed on the
      // delegate, never read from a task-local.
      NetworkTransfer.$category.withValue(.fill) {
        delegate.record(sent: 20, received: 200)
      }
      // Other suites may feed the global sink concurrently; look at ours only.
      #expect(recorder.bytes(in: .thumbnails) == [220])
    }
  }

  @Test("document downloads file their bytes under documents")
  func documentDownloadsRecordDocuments() {
    withSink { recorder in
      // The download's metrics callback runs outside the caller's task, so the
      // ambient category must not leak in.
      NetworkTransfer.$category.withValue(.list) {
        ApiRepository.recordDocumentTransfer(sent: 300, received: 50000)
      }
      #expect(recorder.bytes(in: .documents) == [50300])
    }
  }

  @Test("interactive list traffic is a category of its own")
  func listIsDistinctFromFill() {
    #expect(TransferCategory.list != TransferCategory.fill)
    #expect(TransferCategory.allCases.contains(.list))
  }

  @Test("raw values are stable, so persisted totals keep decoding")
  func rawValuesAreStable() {
    // `TransferStatistics` persists totals keyed by raw value and drops keys it
    // can't decode. Renaming one silently zeroes that category's history.
    let expected: [TransferCategory: String] = [
      .sync: "sync", .list: "list", .fill: "fill", .reconcile: "reconcile",
      .thumbnails: "thumbnails", .documents: "documents", .other: "other",
    ]
    #expect(Set(TransferCategory.allCases) == Set(expected.keys))
    for (category, raw) in expected {
      #expect(category.rawValue == raw)
      #expect(TransferCategory(rawValue: raw) == category)
    }
  }
}
