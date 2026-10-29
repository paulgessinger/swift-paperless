import Common
import DataModel
import Foundation
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite
struct ContentFillTests {
  /// What the fill asked for, batch by batch.
  private actor Requests {
    private(set) var batches: [[UInt]] = []
    func append(_ ids: [UInt]) { batches.append(ids) }
  }

  private struct Unavailable: Error {}

  private static let modified = Date(timeIntervalSince1970: 500)

  private func harness(documents count: UInt, mode: String) async throws -> StoreHarness {
    let documents = (1...count).map { id in
      var document = document(id)
      document.modified = Self.modified
      return document
    }
    let harness = try await StoreHarness.make(documents: documents)
    try harness.database.upsertConnection(
      ConnectionRecord(
        id: harness.serverID,
        url: URL(string: "https://paperless.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "preview"),
        offlineBrowsingMode: mode))
    return harness
  }

  /// Record a fresh text row for each id, as the repository would.
  private static func record(_ ids: [UInt], in database: Database, serverID: UUID) async throws {
    for id in ids {
      try await database.recordFile(
        ContentStore.Key(serverID: serverID, versionID: id, kind: .content), documentID: id,
        size: 1, modified: modified, checksum: nil, storedAt: Date(), lastAccessedAt: Date())
    }
  }

  @Test("The fill asks for every missing text once, newest first, in batches")
  func fillsInBatches() async throws {
    let harness = try await harness(documents: 60, mode: "entireLibrary")
    let requests = Requests()
    let database = harness.database
    let serverID = harness.serverID
    harness.transient.onStoreContents = { ids in
      await requests.append(ids)
      // 60 comes back without a text, and stays missing.
      let sent = ids.filter { $0 != 60 }
      try await Self.record(sent, in: database, serverID: serverID)
      return Set(sent)
    }

    let outcome = try await #require(harness.session.backend).fillContents()

    #expect(outcome.failed == 0)
    let batches = await requests.batches
    #expect(batches.map(\.count) == [25, 25, 10])
    #expect(batches.flatMap { $0 } == Array((1...60).reversed()))
    let left = try await database.documentsNeedingContent(
      serverID: serverID, scope: .library, limit: 100)
    #expect(left.map(\.documentID) == [60])
  }

  @Test("A failed batch is counted and the pass goes on")
  func failedBatchContinues() async throws {
    let harness = try await harness(documents: 30, mode: "entireLibrary")
    let requests = Requests()
    harness.transient.onStoreContents = { ids in
      await requests.append(ids)
      if ids.first == 30 { throw Unavailable() }
      return Set(ids)
    }

    let outcome = try await #require(harness.session.backend).fillContents()

    #expect(outcome.failed == 25)
    #expect(outcome.failure != nil)
    #expect(await requests.batches.map(\.count) == [25, 5])
  }

  @Test("The pass stops before a batch once free space is below the floor")
  func stopsForSpace() async throws {
    let harness = try await harness(documents: 60, mode: "entireLibrary")
    let requests = Requests()
    harness.transient.onStoreContents = { ids in
      await requests.append(ids)
      return Set(ids)
    }
    var checks = 0

    let outcome = try await #require(harness.session.backend).fillContents(
      progress: nil,
      hasRoom: {
        checks += 1
        return checks <= 1
      })

    #expect(outcome.lowStorage)
    #expect(outcome.failed == 0)
    #expect(await requests.batches.map(\.count) == [25])
  }

  @Test("Outside Entire library only the kept documents' texts are fetched")
  func keptScope() async throws {
    let harness = try await harness(documents: 5, mode: "recentlyBrowsed")
    try await harness.database.setKeptOffline(
      serverID: harness.serverID, documentID: 2, kept: true)
    let requests = Requests()
    harness.transient.onStoreContents = { ids in
      await requests.append(ids)
      return Set(ids)
    }

    _ = try await #require(harness.session.backend).fillContents()

    #expect(await requests.batches == [[2]])
  }
}
