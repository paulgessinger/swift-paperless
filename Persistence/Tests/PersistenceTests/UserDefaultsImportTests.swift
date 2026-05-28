import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Legacy connection import (v2 migration)")
struct UserDefaultsImportTests {
  // MARK: - Helpers

  /// A throw-away UserDefaults suite scoped to this test run. Each test
  /// removes its persistent entries on `deinit` so test isolation is
  /// preserved across `swift test` parallelism.
  private final class TempDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() {
      suiteName = "test.persistence.\(UUID().uuidString)"
      defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
      defaults.removePersistentDomain(forName: suiteName)
    }
  }

  /// The on-disk JSON shape `StoredConnection.encode(to:)` produces today,
  /// expressed via plain Encodable types so the fixture doesn't depend on
  /// AppShared.
  private struct LiveStoredConnectionFixture: Encodable {
    var id: UUID
    var url: URL
    var extraHeaders: [HeaderFixture]
    var user: UserFixture
    var identity: String?
    var friendlyName: String?

    struct HeaderFixture: Encodable {
      var id: UUID
      var key: String
      var value: String
    }
    struct UserFixture: Encodable {
      var id: UInt
      var is_superuser: Bool
      var username: String
      var groups: [UInt]?
    }
  }

  private func seedConnections(
    _ dict: [UUID: LiveStoredConnectionFixture],
    in defaults: UserDefaults
  ) throws {
    let data = try JSONEncoder().encode(dict)
    defaults.set(data, forKey: V2_ImportLegacyConnections.userDefaultsKey)
  }

  private func makeFixture(id: UUID = UUID()) -> LiveStoredConnectionFixture {
    .init(
      id: id,
      url: URL(string: "https://paperless.example.com/api/")!,
      extraHeaders: [
        .init(id: UUID(), key: "X-Org", value: "engineering")
      ],
      user: .init(
        id: 42,
        is_superuser: true,
        username: "alice",
        groups: [7, 11]),
      identity: nil,
      friendlyName: "Home")
  }

  /// Construct an in-memory database that runs the v2 import against the
  /// given UserDefaults. This is the unit-of-test for the importer.
  private func makeDatabase(
    seededWith defaults: UserDefaults?
  ) throws -> Persistence.Database {
    try Persistence.Database.inMemory(legacyConnectionsUserDefaults: defaults)
  }

  private func storedRecords(_ database: Persistence.Database) throws -> [ConnectionRecord] {
    try database.writer.read { db in
      try ConnectionRecord.fetchAll(db)
    }
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

  // MARK: - Cases

  @Test("imports seeded UserDefaults into the server table")
  func importsSeededConnections() throws {
    let temp = TempDefaults()
    let id = UUID()
    try seedConnections([id: makeFixture(id: id)], in: temp.defaults)

    let database = try makeDatabase(seededWith: temp.defaults)
    let records = try storedRecords(database)

    #expect(records.count == 1)
    let row = try #require(records.first)
    #expect(row.id == id)
    #expect(row.url == URL(string: "https://paperless.example.com/api/")!)
    #expect(row.user.id == 42)
    #expect(row.user.isSuperUser)
    #expect(row.user.username == "alice")
    #expect(row.user.groups == [7, 11])
    #expect(row.extraHeaders.count == 1)
    #expect(row.extraHeaders.first?.key == "X-Org")
    #expect(row.needsAuth == false)
    #expect(try migrationApplied(database, V2_ImportLegacyConnections.identifier))
  }

  @Test("nil UserDefaults skips the import cleanly")
  func nilDefaultsSkips() throws {
    let database = try makeDatabase(seededWith: nil)
    #expect(try storedRecords(database).isEmpty)
    // Migration is still marked applied — the migrator runs the body once
    // regardless of whether it did any work.
    #expect(try migrationApplied(database, V2_ImportLegacyConnections.identifier))
  }

  @Test("no UserDefaults entry — migration succeeds, no rows")
  func emptyDefaults() throws {
    let temp = TempDefaults()
    let database = try makeDatabase(seededWith: temp.defaults)

    #expect(try storedRecords(database).isEmpty)
    #expect(try migrationApplied(database, V2_ImportLegacyConnections.identifier))
  }

  @Test("malformed JSON: migration succeeds with no rows so we don't loop")
  func malformedJSON() throws {
    let temp = TempDefaults()
    temp.defaults.set(
      Data("{ not real json".utf8),
      forKey: V2_ImportLegacyConnections.userDefaultsKey)

    let database = try makeDatabase(seededWith: temp.defaults)
    #expect(try storedRecords(database).isEmpty)
    #expect(try migrationApplied(database, V2_ImportLegacyConnections.identifier))
  }

  @Test("UserDefaults source data is preserved after import")
  func sourceDataPreserved() throws {
    let temp = TempDefaults()
    let id = UUID()
    try seedConnections([id: makeFixture(id: id)], in: temp.defaults)

    _ = try makeDatabase(seededWith: temp.defaults)

    // After import, the dormant bytes are still present (one-release grace).
    let raw =
      temp.defaults.object(forKey: V2_ImportLegacyConnections.userDefaultsKey)
      as? Data
    #expect(raw != nil)
  }

  @Test("multiple connections all import")
  func multipleConnections() throws {
    let temp = TempDefaults()
    let id1 = UUID()
    let id2 = UUID()
    let id3 = UUID()
    try seedConnections(
      [
        id1: makeFixture(id: id1),
        id2: makeFixture(id: id2),
        id3: makeFixture(id: id3),
      ],
      in: temp.defaults)

    let database = try makeDatabase(seededWith: temp.defaults)

    let records = try storedRecords(database)
    #expect(records.count == 3)
    #expect(Set(records.map(\.id)) == [id1, id2, id3])
  }
}
