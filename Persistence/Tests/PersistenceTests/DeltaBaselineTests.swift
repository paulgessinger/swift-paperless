import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The changed-metadata delta's first-run baseline: the latest `modified` among
/// the server's cached rows, so the first pass walks every change made after
/// the cache was seeded instead of starting above them.
@Suite(
  "DeltaBaseline",
  .bug("https://github.com/paulgessinger/swift-paperless/issues/778", id: 778))
struct DeltaBaselineTests {
  // Fractional seconds: the delta compares against the cursor with a strict
  // `<`, so the baseline has to round-trip exactly.
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t + 0.123_456) }

  private func doc(_ id: UInt, modified: TimeInterval?) -> Document {
    Document(
      id: id, title: "Doc \(id)", asn: nil, documentType: nil, correspondent: nil,
      created: date(1000), tags: [], added: date(1000), modified: modified.map(date),
      originalFileName: nil, archivedFileName: nil, storagePath: nil,
      owner: .user(1), pageCount: 1, notes: NotesPayload(count: 0))
  }

  @Test("an empty cache has no baseline")
  func emptyCacheIsNil() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    #expect(try await database.baselineDeltaWatermark(serverID: server) == nil)
    #expect(try await database.deltaWatermark(serverID: server) == nil)
  }

  @Test("the baseline is the newest cached modified, exactly")
  func newestCachedModified() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.applyChangedDocuments(
      [doc(1, modified: 3000), doc(2, modified: 5000), doc(3, modified: 4000)], serverID: server)

    #expect(try await database.baselineDeltaWatermark(serverID: server) == date(5000))
    #expect(try await database.deltaWatermark(serverID: server) == date(5000))
  }

  @Test("rows without a modified date are ignored")
  func ignoresMissingModified() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.applyChangedDocuments(
      [doc(1, modified: nil), doc(2, modified: 4000)], serverID: server)

    #expect(try await database.baselineDeltaWatermark(serverID: server) == date(4000))
  }

  @Test("rows that all lack a modified date have no baseline")
  func allMissingModifiedIsNil() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.applyChangedDocuments([doc(1, modified: nil)], serverID: server)

    #expect(try await database.allDocumentIDs(serverID: server) == [1])
    #expect(try await database.baselineDeltaWatermark(serverID: server) == nil)
  }

  @Test("another server's rows do not count")
  func isPerServer() async throws {
    let server = UUID()
    let other = UUID()
    let database = try Database.seeded(serverID: server)
    try database.upsertConnection(
      ConnectionRecord(
        id: other,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))
    _ = try await database.applyChangedDocuments([doc(1, modified: 3000)], serverID: server)
    _ = try await database.applyChangedDocuments([doc(1, modified: 9000)], serverID: other)

    #expect(try await database.baselineDeltaWatermark(serverID: server) == date(3000))
  }

  @Test("a failed read throws rather than reading as no baseline")
  func failedReadThrows() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.applyChangedDocuments([doc(1, modified: 3000)], serverID: server)

    // Stand-in for any real read failure. `nil` sends the delta to its
    // server-newest fallback, which would skip the cached rows' changes.
    try await database.writer.write { db in
      try db.execute(sql: "ALTER TABLE document DROP COLUMN modified")
    }

    await #expect(throws: Persistence.DatabaseError.self) {
      _ = try await database.baselineDeltaWatermark(serverID: server)
    }
  }

  @Test("a baseline that cannot be stored throws rather than being returned")
  func failedStoreThrows() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    _ = try await database.applyChangedDocuments([doc(1, modified: 3000)], serverID: server)

    // Stand-in for any real write failure. A returned date would let the delta
    // walk from a baseline that is not on disk.
    try await database.writer.write { db in
      try db.execute(
        sql: """
          CREATE TRIGGER reject_sync_state BEFORE INSERT ON server_sync_state
          BEGIN SELECT RAISE(ABORT, 'rejected'); END
          """)
    }

    await #expect(throws: Persistence.DatabaseError.self) {
      _ = try await database.baselineDeltaWatermark(serverID: server)
    }
    #expect(try await database.deltaWatermark(serverID: server) == nil)
  }
}
