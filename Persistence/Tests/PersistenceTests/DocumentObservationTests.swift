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

  /// Per-server narrowing probe: subscribe, run `foreignWrite` (a write for
  /// *another* server, which the observation's table region cannot exclude),
  /// give the observation time to process it, then run `ownWrite` and return
  /// the next emission.
  ///
  /// If the foreign write leaked an emission, that stale value — not the one
  /// `ownWrite` produced — is what comes back, so the caller's expectation on
  /// the returned value is the assertion. Sequencing the own write behind the
  /// foreign one also proves the stream is still live, i.e. the silence was
  /// narrowing and not a dead subscription.
  private func valueSkippingForeignWrite<T: Sendable>(
    from stream: AsyncThrowingStream<T, Error>,
    foreignWrite: @escaping @Sendable () async throws -> Void,
    ownWrite: @escaping @Sendable () async throws -> Void
  ) async throws -> T {
    try await withTimeout {
      var iterator = stream.makeAsyncIterator()
      _ = try await iterator.next()
      try await foreignWrite()
      // Long enough for the observation to have fetched and (had it not been
      // de-duplicated) emitted before the own write lands, so the two writes
      // cannot be coalesced into one notification.
      try await Task.sleep(for: .milliseconds(250))
      try await ownWrite()
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

  /// Registers a second server so its rows satisfy the `server_id` foreign key.
  private func addServer(to database: Database, host: String) throws -> UUID {
    let id = UUID()
    try database.upsertConnection(
      ConnectionRecord(
        id: id, url: URL(string: "https://\(host).example.com/")!,
        user: .init(id: 1, isSuperUser: false, username: host)))
    return id
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
    try await database.writeQueryPage(
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
    try await database.writeQueryPage(
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
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 4, replaceAll: true)

    let grown = try await value(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10)
    ) {
      try await database.writeQueryPage(
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
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    let updated = try await value(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10)
    ) {
      try await database.upsertDocument(
        self.doc(1, "A-edited"), serverID: server)
    }
    #expect(updated.first(where: { $0.id == 1 })?.document?.title == "A-edited")
  }

  @Test("observeDocumentPrefix re-emits with the gap invisible after a delete")
  func prefixReemitsOnDelete() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B"), doc(3, "C")],
      startPosition: 0, totalCount: 3, replaceAll: true)

    let remaining = try await value(
      from: database.observeDocumentPrefix(queryKey: key, serverID: server, limit: 10)
    ) {
      try await database.deleteDocuments(serverID: server, removedIDs: [2])
    }
    #expect(remaining.map(\.id) == [1, 3])
  }

  // MARK: - observeQueryStatus

  @Test("observeQueryStatus reports counts and re-emits after markStale")
  func queryStatus() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let key = QueryKey(sentinel: "q")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 5, replaceAll: true)

    let initial = try await firstValue(
      from: database.observeQueryStatus(queryKey: key, serverID: server))
    #expect(initial == QueryStatus(totalCount: 5, localCount: 2, orderStale: false))

    let stale = try await value(
      from: database.observeQueryStatus(queryKey: key, serverID: server)
    ) {
      try await database.markQueriesOrderStale(containing: 1, serverID: server)
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
      try await database.upsertDocument(self.doc(1, "A"), serverID: server)
    }
    #expect(appeared?.title == "A")

    let edited = try await value(from: database.observeDocument(serverID: server, id: 1)) {
      try await database.upsertDocument(
        self.doc(1, "A-edited"), serverID: server)
    }
    #expect(edited?.title == "A-edited")
  }

  // MARK: - observeDocumentCount

  @Test("observeDocumentCount emits the current count, then re-emits on write")
  func documentCount() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    let cold = try await firstValue(from: database.observeDocumentCount(serverID: server))
    #expect(cold == 0)

    let afterUpsert = try await value(
      from: database.observeDocumentCount(serverID: server)
    ) {
      try await database.upsertDocuments([self.doc(1, "A"), self.doc(2, "B")], serverID: server)
    }
    #expect(afterUpsert == 2)

    let afterDelete = try await value(
      from: database.observeDocumentCount(serverID: server)
    ) {
      try await database.deleteDocuments(serverID: server, removedIDs: [1])
    }
    #expect(afterDelete == 1)
  }

  // MARK: - Per-server narrowing (#696)

  @Test("observeDocumentPrefix does not emit for another server's write")
  func prefixIgnoresForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA)
    let serverB = try addServer(to: database, host: "b")
    let key = QueryKey(sentinel: "q")
    try await database.writeQueryPage(
      queryKey: key, serverID: serverA, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    let next = try await valueSkippingForeignWrite(
      from: database.observeDocumentPrefix(queryKey: key, serverID: serverA, limit: 10),
      foreignWrite: {
        // Same query key, other server — the sweep's shape exactly.
        try await database.writeQueryPage(
          queryKey: key, serverID: serverB, documents: [self.doc(1, "B-1"), self.doc(2, "B-2")],
          startPosition: 0, totalCount: 2, replaceAll: true)
      },
      ownWrite: {
        try await database.writeQueryPage(
          queryKey: key, serverID: serverA, documents: [self.doc(2, "B")],
          startPosition: 1, totalCount: 2, replaceAll: false)
      })
    #expect(next.map(\.id) == [1, 2])
  }

  @Test("observeQueryStatus does not emit for another server's write")
  func queryStatusIgnoresForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA)
    let serverB = try addServer(to: database, host: "b")
    let key = QueryKey(sentinel: "q")
    try await database.writeQueryPage(
      queryKey: key, serverID: serverA, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    let next = try await valueSkippingForeignWrite(
      from: database.observeQueryStatus(queryKey: key, serverID: serverA),
      foreignWrite: {
        try await database.writeQueryPage(
          queryKey: key, serverID: serverB, documents: [self.doc(9, "B-9")],
          startPosition: 0, totalCount: 9, replaceAll: true)
      },
      ownWrite: {
        try await database.writeQueryPage(
          queryKey: key, serverID: serverA, documents: [self.doc(2, "B")],
          startPosition: 1, totalCount: 2, replaceAll: false)
      })
    #expect(next == QueryStatus(totalCount: 2, localCount: 2, orderStale: false))
  }

  @Test("observeDocument does not emit for another server's write of the same id")
  func documentIgnoresForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, documents: [doc(1, "A")])
    let serverB = try addServer(to: database, host: "b")

    let next = try await valueSkippingForeignWrite(
      from: database.observeDocument(serverID: serverA, id: 1),
      foreignWrite: { try await database.upsertDocument(self.doc(1, "B-1"), serverID: serverB) },
      ownWrite: { try await database.upsertDocument(self.doc(1, "A-edited"), serverID: serverA) })
    #expect(next?.title == "A-edited")
  }

  @Test("observeDocument does not re-emit an identical own-server write")
  func documentIgnoresIdenticalWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, documents: [doc(1, "A")])

    let next = try await valueSkippingForeignWrite(
      from: database.observeDocument(serverID: serverA, id: 1),
      // Same object, written again: a fresh transaction, an identical row.
      foreignWrite: { try await database.upsertDocument(self.doc(1, "A"), serverID: serverA) },
      ownWrite: { try await database.upsertDocument(self.doc(1, "A-edited"), serverID: serverA) })
    #expect(next?.title == "A-edited")
  }

  @Test("observeDocumentCount does not emit for another server's write")
  func documentCountIgnoresForeignServerWrite() async throws {
    let serverA = UUID()
    let database = try Database.seeded(serverID: serverA, documents: [doc(1, "A")])
    let serverB = try addServer(to: database, host: "b")

    let next = try await valueSkippingForeignWrite(
      from: database.observeDocumentCount(serverID: serverA),
      foreignWrite: {
        try await database.upsertDocuments(
          [self.doc(1, "B-1"), self.doc(2, "B-2")], serverID: serverB)
      },
      ownWrite: { try await database.upsertDocument(self.doc(2, "B"), serverID: serverA) })
    #expect(next == 2)
  }
}
