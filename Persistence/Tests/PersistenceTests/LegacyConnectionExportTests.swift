import Foundation
import GRDB
import Testing

@testable import Persistence

/// The debug export is only useful if what it writes is exactly what the v2
/// import reads, so these tests assert the round trip rather than the encoded
/// bytes: export from one database, then let a *fresh* database import the
/// payload — which is precisely the export → wipe → relaunch sequence the
/// action exists to make testable.
@Suite("Legacy connection export")
struct LegacyConnectionExportTests {
  // MARK: - Helpers

  private final class TempDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
      suiteName = "test.persistence.export.\(UUID().uuidString)"
      defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
      defaults.removePersistentDomain(forName: suiteName)
    }
  }

  private func record(
    id: UUID = UUID(),
    friendlyName: String? = "Home server",
    identity: String? = "client-tls",
    needsAuth: Bool = false
  ) -> ConnectionRecord {
    ConnectionRecord(
      id: id,
      url: URL(string: "https://paperless.example.com/api/")!,
      friendlyName: friendlyName,
      identity: identity,
      user: .init(id: 42, isSuperUser: true, username: "alice", groups: [7, 11, 13]),
      extraHeaders: [
        .init(id: UUID(), key: "X-Org", value: "engineering"),
        .init(id: UUID(), key: "Authorization-Hint", value: "bearer"),
      ],
      needsAuth: needsAuth)
  }

  // MARK: - Round trip

  @Test("exported payload re-imports into a fresh database unchanged")
  func roundTripThroughTheImporter() throws {
    let temp = TempDefaults()
    let source = try Persistence.Database.inMemory()
    let stored = record()
    try source.upsertConnection(stored)

    #expect(try source.exportConnectionsToLegacyUserDefaults(temp.defaults) == 1)

    // A brand-new database, as after a wipe: only the v2 migration can put
    // anything in it.
    let reimported = try Persistence.Database.inMemory(
      legacyConnectionsUserDefaults: temp.defaults)
    let records = try reimported.allConnections()

    #expect(records.count == 1)
    let row = try #require(records.first)
    #expect(row.id == stored.id)
    #expect(row.url == stored.url)
    #expect(row.friendlyName == stored.friendlyName)
    #expect(row.identity == stored.identity)
    #expect(row.user == stored.user)
    #expect(row.extraHeaders == stored.extraHeaders)
  }

  @Test("several connections all survive the round trip")
  func roundTripsMultipleConnections() throws {
    let temp = TempDefaults()
    let source = try Persistence.Database.inMemory()
    let first = record(friendlyName: "Home")
    let second = record(friendlyName: "Work", identity: nil)
    try source.upsertConnection(first)
    try source.upsertConnection(second)

    #expect(try source.exportConnectionsToLegacyUserDefaults(temp.defaults) == 2)

    let reimported = try Persistence.Database.inMemory(
      legacyConnectionsUserDefaults: temp.defaults)
    let byID = Dictionary(
      uniqueKeysWithValues: try reimported.allConnections().map { ($0.id, $0) })

    #expect(byID.count == 2)
    #expect(byID[first.id]?.friendlyName == "Home")
    #expect(byID[second.id]?.friendlyName == "Work")
    #expect(byID[second.id]?.identity == nil)
  }

  @Test("needsAuth is not carried by the legacy shape and comes back false")
  func needsAuthIsDropped() throws {
    let temp = TempDefaults()
    let source = try Persistence.Database.inMemory()
    let stored = record(needsAuth: true)
    try source.upsertConnection(stored)
    try source.exportConnectionsToLegacyUserDefaults(temp.defaults)

    let reimported = try Persistence.Database.inMemory(
      legacyConnectionsUserDefaults: temp.defaults)
    #expect(try reimported.allConnections().first?.needsAuth == false)
  }

  @Test("exporting an empty table writes an empty payload, not garbage")
  func exportingNothingIsSafe() throws {
    let temp = TempDefaults()
    let source = try Persistence.Database.inMemory()

    #expect(try source.exportConnectionsToLegacyUserDefaults(temp.defaults) == 0)

    let reimported = try Persistence.Database.inMemory(
      legacyConnectionsUserDefaults: temp.defaults)
    #expect(try reimported.allConnections().isEmpty)
    // The importer must treat it as "nothing to do", not as a corrupt payload.
    #expect(try migrationApplied(reimported, V2_ImportLegacyConnections.identifier))
  }

  @Test("a second export overwrites the first")
  func exportOverwrites() throws {
    let temp = TempDefaults()
    let source = try Persistence.Database.inMemory()
    let stored = record(friendlyName: "Before")
    try source.upsertConnection(stored)
    try source.exportConnectionsToLegacyUserDefaults(temp.defaults)

    try source.upsertConnection(record(id: stored.id, friendlyName: "After"))
    try source.exportConnectionsToLegacyUserDefaults(temp.defaults)

    let reimported = try Persistence.Database.inMemory(
      legacyConnectionsUserDefaults: temp.defaults)
    let records = try reimported.allConnections()
    #expect(records.count == 1)
    #expect(records.first?.friendlyName == "After")
  }

  private func migrationApplied(
    _ database: Persistence.Database,
    _ identifier: String
  ) throws -> Bool {
    try database.writer.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT 1 FROM grdb_migrations WHERE identifier = ?",
        arguments: [identifier]) ?? false
    }
  }
}
