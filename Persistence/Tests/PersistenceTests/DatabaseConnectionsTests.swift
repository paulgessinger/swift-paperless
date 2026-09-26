import Foundation
import Testing

@testable import Persistence

/// Covers the public connection API on `Database` — the surface
/// `ConnectionManager` actually calls. `ConnectionRecordTests` exercises the
/// record's GRDB conformance directly; these tests go through the wrappers,
/// including the observation stream.
@Suite("Database+Connections")
struct DatabaseConnectionsTests {
  // MARK: - Helpers

  private struct ObservationTimeout: Error {}

  private func makeDatabase() throws -> Persistence.Database {
    try Persistence.Database.inMemory()
  }

  private func record(
    id: UUID = UUID(),
    friendlyName: String? = "Home server",
    needsAuth: Bool = false
  ) -> ConnectionRecord {
    ConnectionRecord(
      id: id,
      url: URL(string: "https://paperless.example.com/api/")!,
      friendlyName: friendlyName,
      identity: nil,
      user: .init(id: 1, isSuperUser: false, username: "alice", groups: []),
      extraHeaders: [],
      needsAuth: needsAuth)
  }

  /// Pull snapshots until one satisfies `predicate`.
  ///
  /// `ValueObservation` is free to coalesce writes or to hand us a snapshot
  /// that predates the one we're waiting for, so the tests assert "a state
  /// eventually shows up" rather than pinning an exact emission count. The
  /// enclosing `.timeLimit` keeps a stream that never gets there from hanging.
  private func waitForSnapshot(
    _ iterator: inout AsyncThrowingStream<[ConnectionRecord], Error>.AsyncIterator,
    satisfying predicate: ([ConnectionRecord]) -> Bool
  ) async throws -> [ConnectionRecord] {
    while let records = try await iterator.next() {
      if predicate(records) { return records }
    }
    throw ObservationTimeout()
  }

  // MARK: - CRUD

  @Test("allConnections returns every row")
  func allConnectionsReturnsEveryRow() throws {
    let database = try makeDatabase()
    #expect(try database.allConnections().isEmpty)

    let first = record()
    let second = record()
    try database.upsertConnection(first)
    try database.upsertConnection(second)

    let all = try database.allConnections()
    #expect(Set(all.map(\.id)) == Set([first.id, second.id]))
  }

  @Test("upsertConnection replaces a row with the same id")
  func upsertReplacesSameID() throws {
    let database = try makeDatabase()
    let id = UUID()
    try database.upsertConnection(record(id: id, friendlyName: "Before"))
    try database.upsertConnection(record(id: id, friendlyName: "After"))

    let all = try database.allConnections()
    #expect(all.count == 1)
    #expect(all.first?.friendlyName == "After")
  }

  @Test("deleteConnection reports whether a row went away")
  func deleteReportsOutcome() throws {
    let database = try makeDatabase()
    let stored = record()
    try database.upsertConnection(stored)

    #expect(try database.deleteConnection(id: stored.id))
    #expect(try database.allConnections().isEmpty)
    #expect(try database.deleteConnection(id: stored.id) == false)
  }

  @Test("setNeedsAuth flips only the needs_auth column")
  func setNeedsAuthFlipsOnlyThatColumn() throws {
    let database = try makeDatabase()
    let stored = record(needsAuth: false)
    try database.upsertConnection(stored)

    try database.setNeedsAuth(true, forConnection: stored.id)
    var fetched = try #require(try database.allConnections().first)
    #expect(fetched.needsAuth)
    #expect(fetched.friendlyName == stored.friendlyName)
    #expect(fetched.url == stored.url)

    try database.setNeedsAuth(false, forConnection: stored.id)
    fetched = try #require(try database.allConnections().first)
    #expect(fetched.needsAuth == false)
  }

  @Test("setNeedsAuth on an unknown id is a no-op, not an error")
  func setNeedsAuthUnknownIDIsNoOp() throws {
    let database = try makeDatabase()
    try database.setNeedsAuth(true, forConnection: UUID())
    #expect(try database.allConnections().isEmpty)
  }

  // MARK: - Error wrapping

  @Test("a failed operation surfaces as DatabaseError.operationFailed")
  func failedOperationIsWrapped() throws {
    let database = try makeDatabase()
    // Drop the table out from under the API so the next access fails inside
    // GRDB; the wrapper should re-throw it as our own error type rather than
    // leaking a GRDB error to callers outside the package.
    try database.writer.write { db in
      try db.execute(sql: "DROP TABLE server")
    }

    #expect(throws: DatabaseError.self) {
      _ = try database.allConnections()
    }
    #expect(throws: DatabaseError.self) {
      try database.upsertConnection(record())
    }
  }

  // MARK: - Observation

  @Test("observeConnections emits the current state first", .timeLimit(.minutes(1)))
  func observeEmitsInitialSnapshot() async throws {
    let database = try makeDatabase()
    let stored = record()
    try database.upsertConnection(stored)

    var iterator = database.observeConnections().makeAsyncIterator()
    let initial = try #require(try await iterator.next())
    #expect(initial.map(\.id) == [stored.id])
  }

  @Test("observeConnections emits on insert, update and delete", .timeLimit(.minutes(1)))
  func observeEmitsOnEveryWrite() async throws {
    let database = try makeDatabase()
    var iterator = database.observeConnections().makeAsyncIterator()

    let initial = try #require(try await iterator.next())
    #expect(initial.isEmpty)

    let stored = record(friendlyName: "Before")
    try database.upsertConnection(stored)
    _ = try await waitForSnapshot(&iterator) { $0.map(\.id) == [stored.id] }

    try database.upsertConnection(record(id: stored.id, friendlyName: "After"))
    _ = try await waitForSnapshot(&iterator) { $0.first?.friendlyName == "After" }

    try database.setNeedsAuth(true, forConnection: stored.id)
    _ = try await waitForSnapshot(&iterator) { $0.first?.needsAuth == true }

    try database.deleteConnection(id: stored.id)
    _ = try await waitForSnapshot(&iterator) { $0.isEmpty }
  }

  @Test("a write racing the observation's first fetch is not lost", .timeLimit(.minutes(1)))
  func writeBeforeFirstFetchIsDelivered() async throws {
    let database = try makeDatabase()

    // Mirrors ConnectionManager's bootstrap: read the table, then start
    // observing. A write landing in between must still reach the consumer —
    // either baked into the first value or as a follow-up one — which is why
    // the manager consumes the initial snapshot instead of discarding it as
    // "already applied by the bootstrap read".
    #expect(try database.allConnections().isEmpty)
    let stream = database.observeConnections()
    let stored = record()
    try database.upsertConnection(stored)

    var iterator = stream.makeAsyncIterator()
    _ = try await waitForSnapshot(&iterator) { $0.map(\.id) == [stored.id] }
  }

  @Test("cancelling the consuming task terminates the stream", .timeLimit(.minutes(1)))
  func cancellationTerminatesTheStream() async throws {
    let database = try makeDatabase()
    let stream = database.observeConnections()

    let task = Task {
      var count = 0
      for try await _ in stream {
        count += 1
      }
      return count
    }

    // Give the observation a moment to deliver its initial value, then cancel.
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()

    // Finishes rather than hanging or surfacing a CancellationError to the
    // consumer — observeConnections() swallows that case deliberately.
    _ = try await task.value
  }
}
