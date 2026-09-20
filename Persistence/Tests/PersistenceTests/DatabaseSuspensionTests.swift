import Foundation
import GRDB
import Testing

@testable import Persistence

/// Covers the `0xDEAD10CC` mitigation in `Database+Suspension`.
///
/// On-disk rather than `inMemory()` because suspension acts on a
/// `DatabasePool`'s writer, and `.serialized` because the notifications are
/// process-wide: run in parallel, one test's `suspend()` aborts the others'
/// writes.
@Suite("Database suspension", .serialized)
struct DatabaseSuspensionTests {
  // MARK: - Helpers

  /// The `defer` resumes even on a failed expectation, so a suspension never
  /// outlives its test. Other suites are out of range regardless: they never
  /// opt in.
  private func withDatabase(
    observesSuspensionNotifications: Bool = true,
    _ body: (Persistence.Database) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("suspension-\(UUID().uuidString)", isDirectory: true)
    defer {
      Persistence.Database.resume()
      try? FileManager.default.removeItem(at: directory)
    }
    let database = try Persistence.Database(
      path: directory.appendingPathComponent("swift-paperless.sqlite"),
      observesSuspensionNotifications: observesSuspensionNotifications)
    try await body(database)
  }

  private func connection(id: UUID = UUID()) -> ConnectionRecord {
    ConnectionRecord(
      id: id,
      url: URL(string: "https://paperless.example.com/api/")!,
      friendlyName: "Home server",
      identity: nil,
      user: .init(id: 1, isSuperUser: false, username: "alice", groups: []),
      extraHeaders: [],
      needsAuth: false)
  }

  // MARK: - Tests

  @Test("a write aborted by suspension is reported as a cancellation")
  func suspendedWriteCancels() async throws {
    try await withDatabase { database in
      let server = connection()
      try database.upsertConnection(server)
      try await database.recordQuerySyncError(
        serverID: server.id, queryKey: "default", savedViewName: nil, message: "before")

      Persistence.Database.suspend()

      // Not `DatabaseError.operationFailed`: the sync paths read this as
      // "stopped" and skip recording a per-view failure.
      await #expect(throws: CancellationError.self) {
        try await database.recordQuerySyncError(
          serverID: server.id, queryKey: "default", savedViewName: nil, message: "during")
      }
    }
  }

  @Test("reads keep working while the database is suspended")
  func suspendedReadsStillWork() async throws {
    try await withDatabase { database in
      let server = connection()
      try database.upsertConnection(server)

      Persistence.Database.suspend()

      // `DatabasePool` suspends its writer only, so the UI can still render
      // on the way out.
      #expect(try database.allConnections().map(\.id) == [server.id])
    }
  }

  @Test("resume lets writes through again")
  func resumeRestoresWrites() async throws {
    try await withDatabase { database in
      let server = connection()
      try database.upsertConnection(server)

      Persistence.Database.suspend()
      Persistence.Database.resume()

      try await database.recordQuerySyncError(
        serverID: server.id, queryKey: "default", savedViewName: nil, message: "after")
      let messages = try await database.writer.read { db in
        try String.fetchAll(db, sql: "SELECT message FROM query_sync_error")
      }
      #expect(messages == ["after"])
    }
  }

  @Test("a connection that does not observe the notifications is unaffected")
  func nonObservingConnectionIgnoresSuspension() async throws {
    try await withDatabase(observesSuspensionNotifications: false) { database in
      let server = connection()
      try database.upsertConnection(server)

      Persistence.Database.suspend()

      // What keeps one suite's suspend out of every other suite's writes.
      try await database.recordQuerySyncError(
        serverID: server.id, queryKey: "default", savedViewName: nil, message: "unaffected")
    }
  }
}
