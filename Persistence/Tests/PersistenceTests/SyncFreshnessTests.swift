import Foundation
import Testing

@testable import Persistence

/// The persisted freshness stamps: `last_reconcile_at` backs "Last refreshed",
/// `last_successful_sync_at` the scheduler's throttle.
@Suite("Sync freshness")
struct SyncFreshnessTests {
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func addServer(_ id: UUID, to database: Database) throws {
    try database.upsertConnection(
      ConnectionRecord(
        id: id,
        url: URL(string: "https://\(id.uuidString).example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))
  }

  /// The observation's first value: the stored stamp at the time of the call.
  private func lastReconcileAt(_ database: Database, serverID: UUID) async throws -> Date? {
    for try await stamp in database.observeLastReconcileAt(serverID: serverID) {
      return stamp
    }
    Issue.record("observation finished without a value")
    return nil
  }

  @Test("Stamps of a server without a sync state row read as absent")
  func absentRow() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    #expect(try await lastReconcileAt(database, serverID: server) == nil)
    #expect(try await database.lastSuccessfulSyncs().isEmpty)
  }

  @Test("Both stamps round-trip exactly")
  func roundTrip() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    try await database.setLastReconcileAt(date(1_700_000_000.25), serverID: server)
    try await database.setLastSuccessfulSync(date(1_700_000_100.5), serverID: server)

    #expect(try await lastReconcileAt(database, serverID: server) == date(1_700_000_000.25))
    #expect(try await database.lastSuccessfulSyncs() == [server: date(1_700_000_100.5)])
  }

  @Test("Writing one stamp leaves the other sync state alone")
  func columnsAreIndependent() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.setDeltaWatermark(date(1000), serverID: server)
    try await database.setLibraryCoverageAt(date(2000), serverID: server)
    try await database.setLastSuccessfulSync(date(3000), serverID: server)

    try await database.setLastReconcileAt(date(4000), serverID: server)

    #expect(try await database.deltaWatermark(serverID: server) == date(1000))
    #expect(try await database.libraryCoverageAt(serverID: server) == date(2000))
    #expect(try await database.lastSuccessfulSyncs() == [server: date(3000)])
    #expect(try await lastReconcileAt(database, serverID: server) == date(4000))
  }

  @Test("Every server's last successful sync is listed, and only servers that have one")
  func lastSuccessfulSyncsCoversEveryServer() async throws {
    let first = UUID()
    let second = UUID()
    let neverSynced = UUID()
    let database = try Database.seeded(serverID: first)
    try addServer(second, to: database)
    try addServer(neverSynced, to: database)
    try await database.setLastSuccessfulSync(date(1000), serverID: first)
    try await database.setLastSuccessfulSync(date(2000), serverID: second)
    // A row with other state but no completed pass.
    try await database.setLastReconcileAt(date(3000), serverID: neverSynced)

    #expect(
      try await database.lastSuccessfulSyncs() == [first: date(1000), second: date(2000)])
  }

  @Test("Clearing the cache resets both stamps")
  func clearCacheResets() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.setLastReconcileAt(date(1000), serverID: server)
    try await database.setLastSuccessfulSync(date(2000), serverID: server)

    try await database.clearCache()

    #expect(try await lastReconcileAt(database, serverID: server) == nil)
    #expect(try await database.lastSuccessfulSyncs().isEmpty)
  }
}
