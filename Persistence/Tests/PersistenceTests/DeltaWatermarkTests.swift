import Foundation
import GRDB
import Testing

@testable import Persistence

/// The delta watermark's read contract. `CachingRepository`'s changed-metadata
/// pass treats a `nil` watermark as *"first run"* and re-baselines from the
/// newest document, which discards the real cursor — so *absent* and
/// *unreadable* have to be two different answers, not both `nil`.
@Suite("DeltaWatermark")
struct DeltaWatermarkTests {
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  @Test("an absent row reads as nil without throwing")
  func absentRowIsNil() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    #expect(try await database.deltaWatermark(serverID: server) == nil)
  }

  @Test("a stored watermark round-trips exactly")
  func storedWatermarkRoundTrips() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)

    // Sub-second precision matters: the delta compares `modified` against the
    // cursor with a strict `<`, so a lossy round trip would re-apply or skip.
    let stamp = date(1_700_000_000.123_456)
    try await database.setDeltaWatermark(stamp, serverID: server)

    #expect(try await database.deltaWatermark(serverID: server) == stamp)
  }

  @Test("setting nil clears the watermark without disturbing the fill stamp")
  func settingNilClears() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.setDeltaWatermark(date(5000), serverID: server)
    try await database.setLibraryCoverageAt(date(6000), serverID: server)

    try await database.setDeltaWatermark(nil, serverID: server)

    #expect(try await database.deltaWatermark(serverID: server) == nil)
    #expect(try await database.libraryCoverageAt(serverID: server) == date(6000))
  }

  @Test("one server's watermark is not another's")
  func watermarkIsPerServer() async throws {
    let server = UUID()
    let other = UUID()
    let database = try Database.seeded(serverID: server)
    try database.upsertConnection(
      ConnectionRecord(
        id: other,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))
    try await database.setDeltaWatermark(date(5000), serverID: server)

    #expect(try await database.deltaWatermark(serverID: other) == nil)
  }

  @Test("a failed read throws rather than reading as absent")
  func failedReadThrows() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server)
    try await database.setDeltaWatermark(date(5000), serverID: server)

    // Stand-in for any real read failure (corruption, an I/O error). What is
    // being pinned is that the accessor reports it as an error: collapsing it
    // to `nil` is what let the delta pass re-baseline over a live cursor.
    try await database.writer.write { db in
      try db.execute(sql: "DROP TABLE server_sync_state")
    }

    await #expect(throws: Persistence.DatabaseError.self) {
      _ = try await database.deltaWatermark(serverID: server)
    }
  }
}
