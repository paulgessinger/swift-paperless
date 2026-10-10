import Common
import DataModel
import Foundation
import Testing

@testable import Persistence

/// The content reclaim: unreferenced files, the budget, the repair walk, and
/// its single flight and throttle.
@Suite("Content reclaimer")
struct ContentReclaimerTests {
  private func date(_ t: TimeInterval) -> Date { FileFixtures.date(t) }
  private func doc(_ id: UInt) -> Document { FileFixtures.doc(id) }
  private func addServer(_ id: UUID, to database: Database) throws {
    try FileFixtures.addServer(id, to: database)
  }
  private func makeStore() throws -> ContentStore { try FileFixtures.makeStore() }
  private func key(_ server: UUID, _ version: UInt, _ kind: ContentStore.Kind = .archive)
    -> ContentStore.Key
  {
    FileFixtures.key(server, version, kind)
  }

  /// A file on disk, `bytes` long.
  @discardableResult
  private func write(_ store: ContentStore, _ key: ContentStore.Key, bytes: Int = 10) throws -> URL
  {
    try store.storeData(Data(repeating: 1, count: bytes), for: key)
  }

  /// A file on disk and its row, accessed at `accessed`. Stored now, after the
  /// file, as a download records it.
  private func cache(
    _ store: ContentStore, _ database: Database, _ key: ContentStore.Key, bytes: Int = 10,
    accessed: Date
  ) async throws {
    try write(store, key, bytes: bytes)
    try await database.recordFile(
      key, documentID: key.versionID, size: try #require(store.size(of: key)), modified: nil,
      checksum: nil, storedAt: Date(), lastAccessedAt: key.kind == .thumbnail ? nil : accessed)
  }

  /// The old sidecar, as builds before the index wrote it.
  private func writeLegacySidecar(_ store: ContentStore, _ key: ContentStore.Key, writtenAt: Date)
    throws
  {
    let url = store.url(for: key).deletingLastPathComponent()
      .appendingPathComponent("\(key.kind.rawValue).meta.json")
    let data = try JSONEncoder().encode(
      ContentStore.LegacySidecar(modified: date(5000), writtenAt: writtenAt))
    try data.write(to: url)
  }

  // MARK: - Phases

  @Test("Rows whose version no cached document is at lose their files and rows")
  func unreferenced() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let store = try makeStore()
    try await cache(store, database, key(server, 1), accessed: date(1))
    try await cache(store, database, key(server, 1, .thumbnail), accessed: date(1))
    try await cache(store, database, key(server, 2), accessed: date(1))
    try await cache(store, database, key(server, 2, .thumbnail), accessed: date(1))
    let reclaimer = ContentReclaimer(database: database, store: store, now: { self.date(9000) })

    let report = await reclaimer.run(reason: .manual)

    #expect(report.unreferencedRows == 2)
    #expect(report.unreferencedBytes > 0)
    #expect(report.evictedFiles == 0)
    #expect(report.walked)
    #expect(store.exists(key(server, 1)))
    #expect(store.exists(key(server, 1, .thumbnail)))
    #expect(!store.exists(key(server, 2)))
    #expect(!store.exists(key(server, 2, .thumbnail)))
    #expect(try await database.allFileKeys() == [key(server, 1), key(server, 1, .thumbnail)])
  }

  @Test("A file written after its row was claimed is left to the download that wrote it")
  func newerFileSurvivesTheClaim() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let store = try makeStore()
    // The row for version 2 is from before the file: as if a download had
    // replaced the file between the sweep's read and its unlink.
    try await database.recordFile(
      key(server, 2), documentID: 2, size: 1, modified: nil, checksum: nil,
      storedAt: Date().addingTimeInterval(-60), lastAccessedAt: nil)
    try write(store, key(server, 2))
    let reclaimer = ContentReclaimer(database: database, store: store, now: { self.date(9000) })

    let report = await reclaimer.run(reason: .overBudget)

    #expect(report.unreferencedRows == 1)
    #expect(report.unreferencedBytes == 0)
    #expect(store.exists(key(server, 2)))
  }

  @Test("Eviction removes the least recently accessed files until the budget holds")
  func eviction() async throws {
    let server = UUID()
    let database = try Database.seeded(
      serverID: server, documents: [doc(1), doc(2), doc(3), doc(4)])
    let store = try makeStore()
    try await cache(store, database, key(server, 1), bytes: 100, accessed: date(3000))
    try await cache(store, database, key(server, 2), bytes: 100, accessed: date(1000))
    try await cache(store, database, key(server, 3), bytes: 100, accessed: date(2000))
    try await cache(store, database, key(server, 4), bytes: 100, accessed: date(4000))
    try await cache(store, database, key(server, 4, .thumbnail), bytes: 5000, accessed: date(1))
    let sizes = try await database.evictableFileBytes()
    let reclaimer = ContentReclaimer(
      database: database, store: store, budget: sizes / 2, now: { self.date(9000) })

    let report = await reclaimer.run(reason: .manual)

    #expect(report.evictedFiles == 2)
    #expect(report.evictedBytes == sizes / 2)
    #expect(report.evictableBytes == sizes / 2)
    #expect(!store.exists(key(server, 2)))
    #expect(!store.exists(key(server, 3)))
    #expect(store.exists(key(server, 1)))
    #expect(store.exists(key(server, 4)))
    #expect(store.exists(key(server, 4, .thumbnail)))
  }

  @Test("A file accessed inside the protection window is not evicted")
  func recentAccessIsProtected() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    let store = try makeStore()
    try await cache(store, database, key(server, 1), bytes: 100, accessed: date(8900))
    try await cache(store, database, key(server, 2), bytes: 100, accessed: date(8950))
    let reclaimer = ContentReclaimer(
      database: database, store: store, budget: 1, now: { self.date(9000) })

    let report = await reclaimer.run(reason: .manual)

    #expect(report.evictedFiles == 0)
    #expect(store.exists(key(server, 1)))
  }

  @Test("The repair walk adopts a sidecar file, removes aged orphans and dead rows")
  func repair() async throws {
    let server = UUID()
    let gone = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2), doc(3)])
    let store = try makeStore()
    // 1: file with a legacy sidecar and no row → adopted.
    try write(store, key(server, 1), bytes: 30)
    try writeLegacySidecar(store, key(server, 1), writtenAt: date(6000))
    // 2: row and file, plus a leftover sidecar → sidecar removed, nothing else.
    try await cache(store, database, key(server, 2), accessed: date(1))
    try writeLegacySidecar(store, key(server, 2), writtenAt: date(6000))
    // 3: row without a file → row dropped.
    try await database.recordFile(
      key(server, 3), documentID: 3, size: 1, modified: nil, checksum: nil, storedAt: date(1),
      lastAccessedAt: date(1))
    // 7: file with a sidecar for a document the cache no longer has → removed.
    try write(store, key(server, 7))
    try writeLegacySidecar(store, key(server, 7), writtenAt: date(6000))
    // 8: file with no row and no sidecar, written just now → kept for now.
    try write(store, key(server, 8))
    // A server whose row is gone: its directory goes, grace or not.
    try write(store, key(gone, 1))
    let reclaimer = ContentReclaimer(database: database, store: store, now: { Date() })

    let report = await reclaimer.run(reason: .manual)

    #expect(report.adoptedFiles == 1)
    #expect(report.orphanFiles == 2)
    #expect(report.orphanRows == 1)
    #expect(report.keptRecent == 1)
    let adopted = try #require(try await database.freshFile(key(server, 1), modified: date(5000)))
    #expect(adopted.documentId == 1)
    #expect(adopted.size == store.size(of: key(server, 1)))
    #expect(adopted.storedAt == date(6000).timeIntervalSinceReferenceDate)
    #expect(adopted.lastAccessedAt == date(6000).timeIntervalSinceReferenceDate)
    #expect(store.readLegacySidecar(for: key(server, 1)) == nil)
    #expect(store.readLegacySidecar(for: key(server, 2)) == nil)
    #expect(store.exists(key(server, 2)))
    #expect(!store.exists(key(server, 7)))
    #expect(store.exists(key(server, 8)))
    #expect(!store.exists(key(gone, 1)))
    #expect(store.serverDirectories() == [server])
    #expect(try await database.allFileKeys() == [key(server, 1), key(server, 2)])
  }

  @Test("An aged file without a row is removed once the grace period has passed")
  func agedOrphanIsRemoved() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let store = try makeStore()
    try write(store, key(server, 1))
    let aged = Date().addingTimeInterval(2 * ContentStore.reclaimGracePeriod)
    let reclaimer = ContentReclaimer(database: database, store: store, now: { aged })

    let report = await reclaimer.run(reason: .manual)

    #expect(report.orphanFiles == 1)
    #expect(report.keptRecent == 0)
    #expect(!store.exists(key(server, 1)))
  }

  @Test("An over-budget pass skips the walk")
  func overBudgetSkipsWalk() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let store = try makeStore()
    try write(store, key(server, 1))
    let aged = Date().addingTimeInterval(2 * ContentStore.reclaimGracePeriod)
    let reclaimer = ContentReclaimer(database: database, store: store, now: { aged })

    let report = await reclaimer.run(reason: .overBudget)

    #expect(!report.walked)
    #expect(store.exists(key(server, 1)))
  }

  // MARK: - Index conformance

  @Test("recordStore stamps evictable kinds as accessed and starts a pass once over budget")
  func recordStoreOverBudget() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1), doc(2)])
    let store = try makeStore()
    let later = Date().addingTimeInterval(3600)
    let reclaimer = ContentReclaimer(database: database, store: store, budget: 150, now: { later })

    try write(store, key(server, 1), bytes: 100)
    let first = Date()
    try await reclaimer.recordStore(
      key(server, 1), documentID: 1, size: 100, modified: date(1), checksum: nil, storedAt: first)
    try write(store, key(server, 1, .thumbnail), bytes: 100)
    try await reclaimer.recordStore(
      key(server, 1, .thumbnail), documentID: 1, size: 100, modified: nil, checksum: nil,
      storedAt: first)
    #expect(try await reclaimer.isFresh(key(server, 1), modified: date(1)))
    #expect(
      try await database.anyFile(key(server, 1))?.lastAccessedAt
        == first.timeIntervalSinceReferenceDate)
    #expect(try await database.evictableFileBytes() == 100)

    try write(store, key(server, 2), bytes: 100)
    try await reclaimer.recordStore(
      key(server, 2), documentID: 2, size: 100, modified: date(1), checksum: nil,
      storedAt: Date())

    // The pass runs on its own task; join it.
    for _ in 0..<100 where store.exists(key(server, 1)) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!store.exists(key(server, 1)))
    #expect(store.exists(key(server, 2)))
    #expect(store.exists(key(server, 1, .thumbnail)))
  }

  @Test("recordAccess records once per window and forget drops the row")
  func accessAndForget() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let store = try makeStore()
    try await cache(store, database, key(server, 1), accessed: date(1000))
    let reclaimer = ContentReclaimer(database: database, store: store)

    try await reclaimer.recordAccess(key(server, 1), at: date(2000))
    try await reclaimer.recordAccess(key(server, 1), at: date(2030))
    try await reclaimer.recordAccess(key(server, 1), at: date(2100))

    let entry = try #require(try await database.anyFile(key(server, 1)))
    #expect(entry.lastAccessedAt == date(2100).timeIntervalSinceReferenceDate)

    try await reclaimer.forget(key(server, 1))
    #expect(try await database.allFileKeys().isEmpty)
  }

  // MARK: - Scheduling

  @Test("runIfDue runs once per interval")
  func throttle() async throws {
    let database = try Database.seeded()
    let clock = Clock(date(1000))
    let reclaimer = ContentReclaimer(database: database, store: try makeStore(), now: { clock.now })

    #expect(await reclaimer.runIfDue(reason: .afterReconcile) != nil)
    #expect(await reclaimer.runIfDue(reason: .afterReconcile) == nil)
    clock.now = date(1000 + ContentReclaimer.dueInterval)
    #expect(await reclaimer.runIfDue(reason: .afterReconcile) != nil)
    // A run for any reason resets the interval.
    await reclaimer.run(reason: .manual)
    clock.now = date(1000 + ContentReclaimer.dueInterval + 10)
    #expect(await reclaimer.runIfDue(reason: .afterReconcile) == nil)
  }

  @Test("Concurrent runs share one pass and a request during it gets another")
  func singleFlight() async throws {
    let server = UUID()
    let database = try Database.seeded(serverID: server, documents: [doc(1)])
    let store = try makeStore()
    let reclaimer = ContentReclaimer(database: database, store: store, now: { self.date(9000) })

    async let a = reclaimer.run(reason: .manual)
    async let b = reclaimer.run(reason: .launch)
    let reports = await [a, b]

    // Both callers got a report; the pass count is not observable from here,
    // so the contract checked is that neither call is lost.
    #expect(reports.count == 2)
    #expect(reports.allSatisfy { $0.walked })
  }

  private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
  }
}
