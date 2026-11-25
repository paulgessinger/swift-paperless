import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@MainActor
@Suite("Local evaluation of a document list")
struct LocalEvaluationTests {
  /// Holds every list fetch until released.
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

  private var filter: FilterState {
    FilterState.empty.with {
      $0.sorting = .init(field: .created, order: .descending)
      $0.searchMode = .title
      $0.searchText = "document 2"
    }
  }

  @Test("The device's answer becomes the list's cached order, marked as local")
  func writesLocalOrder() async throws {
    let harness = try await StoreHarness.make(documents: (1...3).map { document($0) })
    let key = try #require(harness.store.documentQueryKey(filter: filter))

    let evaluation = try await harness.store.evaluateDocumentQueryLocally(filter: filter)

    #expect(evaluation?.documents == 3)
    let status = try #require(try await harness.store.queryStatus(queryKey: key))
    #expect(status.localEvaluation == evaluation)
    #expect(!status.isComplete)
    let entries = try await harness.database.queryDocuments(
      queryKey: key, serverID: harness.serverID, limit: 10)
    #expect(entries.map(\.id) == [2])
  }

  @Test("A fill that reaches the server replaces the device's answer and clears the mark")
  func fillReplacesLocalOrder() async throws {
    let harness = try await StoreHarness.make(documents: (1...3).map { document($0) })
    // The server knows a matching document the device hasn't cached.
    for id: UInt in [2, 12] {
      var matching = document(id)
      matching.title = "Document 2 on the server (\(id))"
      _ = try await harness.transient.update(document: matching)
    }
    let key = try #require(harness.store.documentQueryKey(filter: filter))
    _ = try await harness.store.evaluateDocumentQueryLocally(filter: filter)

    let handle = try await harness.store.fillDocumentQuery(filter: filter)
    try await handle.awaitCompletion()

    let status = try #require(try await harness.store.queryStatus(queryKey: key))
    #expect(status.localEvaluation == nil)
    #expect(status.isComplete)
    let entries = try await harness.database.queryDocuments(
      queryKey: key, serverID: harness.serverID, limit: 10)
    #expect(Set(entries.map(\.id)) == [2, 12])
  }

  @Test("While a fill owns the query, the device doesn't answer over it")
  func stepsAsideForFill() async throws {
    let harness = try await StoreHarness.make(documents: (1...3).map { document($0) })
    let gate = Gate()
    harness.transient.onRequest = { name in await gate.pass(name) }
    let filter = filter
    let key = try #require(harness.store.documentQueryKey(filter: filter))

    let fill = Task { try await harness.store.fillDocumentQuery(filter: filter) }
    for _ in 0..<500 where await !gate.entered {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await gate.entered)

    #expect(try await harness.store.evaluateDocumentQueryLocally(filter: filter) == nil)
    let during = try #require(try await harness.store.queryStatus(queryKey: key))
    #expect(during.localEvaluation == nil)
    #expect(during.localCount == 0)

    await gate.release()
    try await fill.value.awaitCompletion()
  }

  @Test("While a fill is still waiting for the server, the device may answer meanwhile")
  func answersWhileFillWaits() async throws {
    let harness = try await StoreHarness.make(documents: (1...3).map { document($0) })
    var onServer = document(12)
    onServer.title = "Document 2 on the server"
    _ = try await harness.transient.update(document: onServer)
    let gate = Gate()
    harness.transient.onRequest = { name in await gate.pass(name) }
    let filter = filter
    let key = try #require(harness.store.documentQueryKey(filter: filter))

    let fill = Task { try await harness.store.fillDocumentQuery(filter: filter) }
    for _ in 0..<500 where await !gate.entered {
      try await Task.sleep(for: .milliseconds(5))
    }

    // The fill owns the query and has written nothing: the device answers.
    let evaluation = try await harness.store.evaluateDocumentQueryLocally(
      filter: filter, whileFilling: true)
    #expect(evaluation != nil)
    let meanwhile = try await harness.database.queryDocuments(
      queryKey: key, serverID: harness.serverID, limit: 10)
    #expect(meanwhile.map(\.id) == [2])

    // The server's first page replaces it.
    await gate.release()
    try await fill.value.awaitCompletion()
    let status = try #require(try await harness.store.queryStatus(queryKey: key))
    #expect(status.localEvaluation == nil)
    let entries = try await harness.database.queryDocuments(
      queryKey: key, serverID: harness.serverID, limit: 10)
    #expect(entries.map(\.id) == [12])

    // And from then on the device holds back.
    #expect(
      try await harness.store.evaluateDocumentQueryLocally(filter: filter, whileFilling: true)
        == nil)
  }
}
