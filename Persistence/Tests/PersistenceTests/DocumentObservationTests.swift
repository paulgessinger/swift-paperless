import DataModel
import Foundation
import Testing

@testable import Persistence

@Suite("DocumentObservation")
struct DocumentObservationTests {
  // MARK: - Helpers

  private struct TimeoutError: Error {}

  private func firstValue<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>
  ) async throws -> T {
    try await withTimeout {
      var iterator = stream.makeAsyncIterator()
      guard let value = try await iterator.next() else { throw TimeoutError() }
      return value
    }
  }

  /// The emission that lands *after* `action` runs (consumes the initial value
  /// first, which also guarantees the observation is subscribed before the write).
  private func value<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>,
    afterSubscribe action: @escaping @Sendable () async throws -> Void
  ) async throws -> T {
    try await withTimeout {
      var iterator = stream.makeAsyncIterator()
      _ = try await iterator.next()
      try await action()
      guard let value = try await iterator.next() else { throw TimeoutError() }
      return value
    }
  }

  private func withTimeout<T: Sendable>(
    seconds: Double = 3,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw TimeoutError()
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  private func doc(_ id: UInt, _ title: String) -> Document {
    Document(
      id: id, title: title, created: Date(timeIntervalSince1970: 1000), tags: [], owner: .user(1))
  }

  // MARK: - observeDocumentPrefix

  @Test("observeDocumentPrefix emits the current window in replay order")
  func prefixInitial() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "C"), doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 3, replaceAll: true)

    let initial = try await firstValue(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10))
    #expect(initial.map(\.id) == [3, 1, 2])
  }

  @Test("observeDocumentPrefix honours the limit (prefix, not the whole set)")
  func prefixLimited() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: (1...5).map { doc($0, "d\($0)") },
      startPosition: 0, totalCount: 5, replaceAll: true)

    let window = try await firstValue(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 2))
    #expect(window.map(\.id) == [1, 2])
  }

  @Test("observeDocumentPrefix re-emits as a background fill appends pages")
  func prefixReemitsOnAppend() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 4, replaceAll: true)

    let grown = try await value(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10)
    ) {
      try database.writeQueryPage(
        queryKey: key, serverID: server, documents: [self.doc(3, "C"), self.doc(4, "D")],
        startPosition: 2, totalCount: 4, replaceAll: false)
    }
    #expect(grown.map(\.id) == [1, 2, 3, 4])
  }

  @Test("observeDocumentPrefix re-emits an in-place metadata update")
  func prefixReemitsOnUpsert() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    let updated = try await value(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10)
    ) {
      try database.upsertDocument(
        self.doc(1, "A-edited"), serverID: server, projectionLevel: .full)
    }
    #expect(updated.first(where: { $0.id == 1 })?.title == "A-edited")
  }

  @Test("observeDocumentPrefix re-emits with the gap invisible after a delete")
  func prefixReemitsOnDelete() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B"), doc(3, "C")],
      startPosition: 0, totalCount: 3, replaceAll: true)

    let remaining = try await value(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10)
    ) {
      try database.deleteDocuments(serverID: server, removedIDs: [2])
    }
    #expect(remaining.map(\.id) == [1, 3])
  }

  // MARK: - observeQueryStatus

  @Test("observeQueryStatus reports counts and re-emits after markStale")
  func queryStatus() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 5, replaceAll: true)

    let initial = try await firstValue(
      from: database.observeQueryStatus(queryKey: key, serverID: server))
    #expect(initial == QueryStatus(totalCount: 5, localCount: 2, orderStale: false))

    let stale = try await value(
      from: database.observeQueryStatus(queryKey: key, serverID: server)
    ) {
      try database.markQueriesOrderStale(containing: 1, serverID: server)
    }
    #expect(stale.orderStale == true)
  }

  // MARK: - observeDocument

  @Test("observeDocument emits nil cold, then the value, then in-place updates")
  func singleDocument() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    let cold = try await firstValue(from: database.observeDocument(serverID: server, id: 1))
    #expect(cold == nil)

    let appeared = try await value(from: database.observeDocument(serverID: server, id: 1)) {
      try database.upsertDocument(self.doc(1, "A"), serverID: server, projectionLevel: .full)
    }
    #expect(appeared?.title == "A")

    let edited = try await value(from: database.observeDocument(serverID: server, id: 1)) {
      try database.upsertDocument(
        self.doc(1, "A-edited"), serverID: server, projectionLevel: .full)
    }
    #expect(edited?.title == "A-edited")
  }
}
