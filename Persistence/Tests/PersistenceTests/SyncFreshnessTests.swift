import Foundation
import Testing

@testable import Persistence

/// The persisted freshness stamp, `last_refreshed_at`: "Last refreshed" and
/// the scheduler's throttle and order.
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
  private func lastRefreshedAt(_ database: Database, serverID: UUID) async throws -> Date? {
    for try await stamp in database.observeLastRefreshedAt(serverID: serverID) {
      return stamp
    }
    Issue.record("observation finished without a value")
    return nil
  }

  @Test("The stamp of a server without a sync state row reads as absent")
  func absentRow() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    #expect(try await lastRefreshedAt(database, serverID: server) == nil)
    #expect(try await database.lastRefreshes().isEmpty)
  }

  @Test("The stamp round-trips exactly")
  func roundTrip() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    try await database.setLastRefreshedAt(date(1_700_000_000.25), serverID: server)

    #expect(try await lastRefreshedAt(database, serverID: server) == date(1_700_000_000.25))
    #expect(try await database.lastRefreshes() == [server: date(1_700_000_000.25)])
  }

  @Test("Writing the stamp leaves the other sync state alone")
  func columnsAreIndependent() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.setDeltaWatermark(date(1000), serverID: server)
    try await database.setLibraryCoverageAt(date(2000), serverID: server)

    try await database.setLastRefreshedAt(date(4000), serverID: server)

    #expect(try await database.deltaWatermark(serverID: server) == date(1000))
    #expect(try await database.libraryCoverageAt(serverID: server) == date(2000))
    #expect(try await lastRefreshedAt(database, serverID: server) == date(4000))
  }

  @Test("Every server's stamp is listed, and only servers that have one")
  func lastRefreshesCoversEveryServer() async throws {
    let first = UUID()
    let second = UUID()
    let neverRefreshed = UUID()
    let database = try Database.seeded(serverID: first)
    try addServer(second, to: database)
    try addServer(neverRefreshed, to: database)
    try await database.setLastRefreshedAt(date(1000), serverID: first)
    try await database.setLastRefreshedAt(date(2000), serverID: second)
    // A row with other state but no refresh.
    try await database.setDeltaWatermark(date(3000), serverID: neverRefreshed)

    #expect(
      try await database.lastRefreshes() == [first: date(1000), second: date(2000)])
  }

  @Test("Clearing the cache resets the stamp")
  func clearCacheResets() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.setLastRefreshedAt(date(1000), serverID: server)

    try await database.clearCache()

    #expect(try await lastRefreshedAt(database, serverID: server) == nil)
    #expect(try await database.lastRefreshes().isEmpty)
  }
}
