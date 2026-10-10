import Foundation
import Testing

@testable import Persistence

/// The sync step record, `sync_run`: begin/end, the per-server cap, and the
/// launch-time close of interrupted rows.
@Suite("Sync runs")
struct SyncRunTests {
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func addServer(_ id: UUID, to database: Database) throws {
    try database.upsertConnection(
      ConnectionRecord(
        id: id,
        url: URL(string: "https://\(id.uuidString).example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))
  }

  @Test("A step's row round-trips through begin and end")
  func roundTrip() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let run = UUID()

    let id = try await database.beginSyncStep(
      runID: run, serverID: server, trigger: "sweep", step: "reconcile", at: date(1000))
    let open = try await database.syncRuns()
    #expect(open.map(\.isOpen) == [true])
    #expect(open.first?.outcome == nil)

    try await database.endSyncStep(
      id: id, outcome: "partial", message: "one view rejected", succeeded: 7, failed: 1,
      at: date(1002.5))

    let entries = try await database.syncRuns()
    #expect(entries.count == 1)
    let entry = try #require(entries.first)
    #expect(entry.id == id)
    #expect(entry.runID == run)
    #expect(entry.serverID == server)
    #expect(entry.trigger == "sweep")
    #expect(entry.step == "reconcile")
    #expect(entry.startedAt == date(1000))
    #expect(entry.endedAt == date(1002.5))
    #expect(entry.outcome == "partial")
    #expect(entry.message == "one view rejected")
    #expect(entry.succeeded == 7)
    #expect(entry.failed == 1)
    #expect(!entry.isOpen)
  }

  @Test("Rows come back newest first")
  func newestFirst() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    for t in [10.0, 30.0, 20.0] {
      _ = try await database.beginSyncStep(
        runID: UUID(), serverID: server, trigger: "foreground", step: "elements", at: date(t))
    }

    #expect(try await database.syncRuns().map(\.startedAt) == [date(30), date(20), date(10)])
    #expect(try await database.syncRuns(limit: 1).map(\.startedAt) == [date(30)])
  }

  @Test("The cap keeps a server's newest rows and leaves other servers alone")
  func capPerServer() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try Database.seeded(serverID: serverA)
    try addServer(serverB, to: database)
    let cap = Database.syncRunCapPerServer

    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: serverB, trigger: "sweep", step: "elements", at: date(0))
    for i in 0..<(cap + 3) {
      _ = try await database.beginSyncStep(
        runID: UUID(), serverID: serverA, trigger: "foreground", step: "elements",
        at: date(Double(i)))
    }

    let entries = try await database.syncRuns(limit: 10_000)
    let a = entries.filter { $0.serverID == serverA }
    #expect(a.count == cap)
    // The three oldest went.
    #expect(a.last?.startedAt == date(3))
    #expect(entries.filter { $0.serverID == serverB }.count == 1)
  }

  @Test("Background-task rows have their own cap")
  func capForTasks() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let cap = Database.syncRunCapForTasks

    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: server, trigger: "refreshTask", step: "elements", at: date(0))
    for i in 0..<(cap + 1) {
      _ = try await database.beginSyncStep(
        runID: UUID(), serverID: nil, trigger: "refreshTask", step: "task", at: date(Double(i)))
    }

    let entries = try await database.syncRuns(limit: 10_000)
    #expect(entries.filter { $0.serverID == nil }.count == cap)
    #expect(entries.filter { $0.serverID == server }.count == 1)
  }

  @Test("Deleting a server cascades to its rows, not to task rows")
  func cascadeOnServerDelete() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: server, trigger: "sweep", step: "elements")
    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: nil, trigger: "refreshTask", step: "task")

    try database.deleteConnection(id: server)

    #expect(try await database.syncRuns().map(\.serverID) == [nil])
  }

  @Test("Closing interrupted steps touches only open rows older than the cutoff")
  func closeInterrupted() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let done = try await database.beginSyncStep(
      runID: UUID(), serverID: server, trigger: "sweep", step: "elements", at: date(1))
    try await database.endSyncStep(id: done, outcome: "ok", at: date(2))
    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: server, trigger: "sweep", step: "reconcile", at: date(3))
    // Started by the current process: still running, not interrupted.
    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: server, trigger: "sweep", step: "elements", at: date(40))

    let closed = try await database.closeInterruptedSyncSteps(before: date(10), at: date(50))

    #expect(closed == 1)
    let entries = try await database.syncRuns()
    #expect(entries.map(\.outcome) == [nil, "interrupted", "ok"])
    #expect(entries[1].endedAt == date(50))
    #expect(entries[2].endedAt == date(2))
  }

  @Test("clearCache keeps the record; clearSyncRuns drops it")
  func clearing() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.beginSyncStep(
      runID: UUID(), serverID: server, trigger: "sweep", step: "elements")

    try await database.clearCache()
    #expect(try await database.syncRuns().count == 1)

    try await database.clearSyncRuns()
    #expect(try await database.syncRuns().isEmpty)
  }
}
