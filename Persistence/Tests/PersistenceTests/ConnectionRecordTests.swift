import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("ConnectionRecord")
struct ConnectionRecordTests {
  // MARK: - Helpers

  private func makeDatabase() throws -> Persistence.Database {
    try Persistence.Database.inMemory()
  }

  private func fullRecord(
    id: UUID = UUID(),
    needsAuth: Bool = false
  ) -> ConnectionRecord {
    ConnectionRecord(
      id: id,
      url: URL(string: "https://paperless.example.com/api/")!,
      friendlyName: "Home server",
      identity: "client-tls",
      user: .init(
        id: 42,
        isSuperUser: true,
        username: "alice",
        groups: [7, 11, 13]),
      extraHeaders: [
        .init(id: UUID(), key: "X-Org", value: "engineering"),
        .init(id: UUID(), key: "Authorization-Hint", value: "bearer"),
      ],
      needsAuth: needsAuth)
  }

  // MARK: - Roundtrip

  @Test("roundtrip preserves all fields")
  func roundtripPreservesAllFields() throws {
    let database = try makeDatabase()
    let original = fullRecord()
    try database.writer.write { db in
      try original.insert(db)
    }
    let fetched = try database.writer.read { db in
      try ConnectionRecord.fetchOne(db, key: original.id)
    }
    #expect(fetched == original)
  }

  @Test("roundtrip with nil friendlyName and identity")
  func roundtripWithNilOptionalFields() throws {
    let database = try makeDatabase()
    var original = fullRecord()
    original.friendlyName = nil
    original.identity = nil
    try database.writer.write { db in
      try original.insert(db)
    }
    let fetched = try database.writer.read { db in
      try #require(try ConnectionRecord.fetchOne(db, key: original.id))
    }
    #expect(fetched.friendlyName == nil)
    #expect(fetched.identity == nil)
    #expect(fetched == original)
  }

  @Test("empty extraHeaders roundtrips as [] not null")
  func emptyExtraHeadersRoundtrip() throws {
    let database = try makeDatabase()
    var original = fullRecord()
    original.extraHeaders = []
    try database.writer.write { db in
      try original.insert(db)
    }
    let fetched = try database.writer.read { db in
      try #require(try ConnectionRecord.fetchOne(db, key: original.id))
    }
    #expect(fetched.extraHeaders == [])
  }

  @Test("user groups array order and values preserved")
  func userGroupsPreserved() throws {
    let database = try makeDatabase()
    let original = fullRecord()
    try database.writer.write { db in
      try original.insert(db)
    }
    let fetched = try database.writer.read { db in
      try #require(try ConnectionRecord.fetchOne(db, key: original.id))
    }
    #expect(fetched.user.groups == [7, 11, 13])
  }

  @Test("extra header ids are preserved verbatim")
  func headerIDsPreserved() throws {
    let database = try makeDatabase()
    let h1Id = UUID()
    let h2Id = UUID()
    let original = ConnectionRecord(
      id: UUID(),
      url: URL(string: "https://example.com/")!,
      user: .init(id: 1, isSuperUser: false, username: "u"),
      extraHeaders: [
        .init(id: h1Id, key: "A", value: "1"),
        .init(id: h2Id, key: "B", value: "2"),
      ])
    try database.writer.write { db in
      try original.insert(db)
    }
    let fetched = try database.writer.read { db in
      try #require(try ConnectionRecord.fetchOne(db, key: original.id))
    }
    let ids = fetched.extraHeaders.map { $0.id }
    #expect(ids == [h1Id, h2Id])
  }

  @Test("needsAuth defaults to false and explicit true persists")
  func needsAuthDefaultAndExplicit() throws {
    let database = try makeDatabase()
    let off = fullRecord(needsAuth: false)
    let on = fullRecord(needsAuth: true)
    try database.writer.write { db in
      try off.insert(db)
      try on.insert(db)
    }
    let fetched = try database.writer.read { db in
      (
        try #require(try ConnectionRecord.fetchOne(db, key: off.id)).needsAuth,
        try #require(try ConnectionRecord.fetchOne(db, key: on.id)).needsAuth
      )
    }
    #expect(fetched.0 == false)
    #expect(fetched.1 == true)
  }

  @Test("upsert by primary key replaces existing row")
  func upsertReplacesExisting() throws {
    let database = try makeDatabase()
    let id = UUID()
    var record = fullRecord(id: id)
    try database.writer.write { db in
      try record.insert(db)
    }
    record.friendlyName = "Renamed"
    record.needsAuth = true
    try database.writer.write { db in
      try record.upsert(db)
    }
    let fetched = try database.writer.read { db in
      try #require(try ConnectionRecord.fetchOne(db, key: id))
    }
    #expect(fetched.friendlyName == "Renamed")
    #expect(fetched.needsAuth == true)
  }

  @Test("delete by id removes the row")
  func deleteRemovesRow() throws {
    let database = try makeDatabase()
    let record = fullRecord()
    try database.writer.write { db in
      try record.insert(db)
      let removed = try ConnectionRecord.deleteOne(db, key: record.id)
      #expect(removed)
    }
    let exists = try database.writer.read { db in
      try ConnectionRecord.fetchOne(db, key: record.id) != nil
    }
    #expect(!exists)
  }

  @Test("JSON columns hold valid storage-shaped JSON")
  func jsonColumnsAreValidJSON() throws {
    let database = try makeDatabase()
    let record = fullRecord()
    try database.writer.write { db in
      try record.insert(db)
    }
    // Pull the raw column values back out and re-decode with the storage
    // decoder to confirm the on-disk JSON matches what the record produced
    // (independent of GRDB's record mapping).
    let raw = try database.writer.read { db -> (Data, Data) in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT user, extra_headers FROM server WHERE id = ?",
          arguments: [record.id]))
      let userText: String = row["user"]
      let headersText: String = row["extra_headers"]
      return (Data(userText.utf8), Data(headersText.utf8))
    }
    let user = try ConnectionRecord.storageDecoder.decode(
      ConnectionRecord.StoredUser.self, from: raw.0)
    let headers = try ConnectionRecord.storageDecoder.decode(
      [ConnectionRecord.StoredHeader].self, from: raw.1)
    #expect(user == record.user)
    #expect(headers == record.extraHeaders)
  }
}
