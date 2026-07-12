import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("Sync-state cursors")
struct SyncStateTests {
  @Test("v8 adds last_sync_at to server_sync_state")
  func v8AddsLastSyncAt() throws {
    let database = try Database.inMemory()
    try database.writer.read { db in
      let columns = Set(try db.columns(in: "server_sync_state").map(\.name))
      #expect(columns == ["server_id", "delta_watermark", "library_coverage_at", "last_sync_at"])
      let column = try #require(
        try db.columns(in: "server_sync_state").first(where: { $0.name == "last_sync_at" }))
      #expect(column.type.uppercased() == "REAL")
      #expect(!column.isNotNull)
    }
  }

  @Test("lastSyncAt round-trips and starts nil")
  func lastSyncAtRoundTrip() throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    #expect(try database.lastSyncAt(serverID: server) == nil)

    let stamp = Date(timeIntervalSinceReferenceDate: 12345.678)
    try database.setLastSyncAt(stamp, serverID: server)
    #expect(try database.lastSyncAt(serverID: server) == stamp)

    try database.setLastSyncAt(nil, serverID: server)
    #expect(try database.lastSyncAt(serverID: server) == nil)
  }

  @Test("setLastSyncAt preserves the row's other cursors")
  func preservesSiblingCursors() throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let watermark = Date(timeIntervalSinceReferenceDate: 1000)
    let coverage = Date(timeIntervalSinceReferenceDate: 2000)
    try database.setDeltaWatermark(watermark, serverID: server)
    try database.setLibraryCoverageAt(coverage, serverID: server)

    try database.setLastSyncAt(Date(timeIntervalSinceReferenceDate: 3000), serverID: server)

    #expect(try database.deltaWatermark(serverID: server) == watermark)
    #expect(try database.libraryCoverageAt(serverID: server) == coverage)
  }

  @Test("lastSyncAts returns only servers with a stamp")
  func bulkRead() throws {
    let a = UUID()
    let b = UUID()
    let database = try Database.seeded(serverID: a)
    try database.upsertConnection(
      ConnectionRecord(
        id: b,
        url: URL(string: "https://second.example.com/api/")!,
        user: .init(id: 2, isSuperUser: false, username: "second")))

    let stamp = Date(timeIntervalSinceReferenceDate: 42)
    try database.setLastSyncAt(stamp, serverID: a)
    // b gets a row but no stamp — must be absent from the bulk read.
    try database.setDeltaWatermark(Date(), serverID: b)

    #expect(try database.lastSyncAts() == [a: stamp])
  }

  @Test("clearCache resets last_sync_at")
  func clearCacheResets() throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try database.setLastSyncAt(Date(), serverID: server)

    try database.clearCache()

    #expect(try database.lastSyncAt(serverID: server) == nil)
  }

  @Test("observeLastSyncAt emits current value and updates")
  func observation() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    let stamp = Date(timeIntervalSinceReferenceDate: 7)

    var iterator = database.observeLastSyncAt(serverID: server).makeAsyncIterator()
    #expect(try await iterator.next() == .some(nil))

    try database.setLastSyncAt(stamp, serverID: server)
    #expect(try await iterator.next() == .some(stamp))
  }
}
