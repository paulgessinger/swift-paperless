import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

@Suite("DocumentCache")
struct DocumentCacheTests {
  // MARK: - Helpers

  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  private func doc(_ id: UInt, _ title: String, asn: UInt? = nil) -> Document {
    Document(
      id: id, title: title, asn: asn, created: date(1000), tags: [],
      owner: .user(1))
  }

  /// A fresh in-memory DB with one server registered.
  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  private func record(
    _ database: Persistence.Database, _ server: UUID, _ id: UInt
  ) throws -> DocumentRecord? {
    try database.writer.read { db in
      try DocumentRecord
        .filter(Column("server_id") == server && Column("id") == id)
        .fetchOne(db)
    }
  }

  // MARK: - Round-trip

  @Test("DocumentRecord round-trips a fully-populated document, including versions")
  func roundTrip() async throws {
    let server = UUID()
    let database = try database(server)

    var input = Document(
      id: 1, title: "Invoice", asn: 42, documentType: 2, correspondent: 3,
      created: date(1000), tags: [4, 5], added: date(2000), modified: date(3000),
      originalFileName: "scan.pdf", archivedFileName: "archive.pdf",
      storagePath: 6, owner: .user(7), pageCount: 3, notes: NotesPayload(count: 2),
      versions: [
        DocumentVersion(id: 1, added: date(1000), isRoot: true),
        DocumentVersion(id: 9, added: date(5000), label: "v2", isRoot: false),
      ])
    // Mirror how a document arrives from the API (permissions assigned post-init,
    // which also sets setPermissions via didSet) so equality holds round-trip.
    input.permissions = Permissions { $0.view = .init(users: [1, 2]) }

    try database.upsertDocument(input, serverID: server, projectionLevel: .detail)
    let output = try database.document(serverID: server, id: 1)

    #expect(output == input)
    #expect(output?.currentVersionID == 9)  // newest by `added`
    #expect(output?.rootVersionID == 1)
  }

  @Test("document(asn:) resolves via the indexed column")
  func resolvesByAsn() async throws {
    let server = UUID()
    let database = try database(server)
    try database.upsertDocuments(
      [doc(1, "A", asn: 100), doc(2, "B", asn: 200)],
      serverID: server, projectionLevel: .metadata)

    #expect(try database.document(serverID: server, asn: 200)?.id == 2)
    #expect(try database.document(serverID: server, asn: 999) == nil)
  }

  // MARK: - query_order replay

  @Test("queryDocuments replays the server order, not id/sort order")
  func replaysServerOrder() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    // Written out of natural id order.
    try database.writeQueryPage(
      queryKey: key, serverID: server,
      documents: [doc(3, "C"), doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 3, replaceAll: true)

    let replayed = try database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(replayed.map(\.id) == [3, 1, 2])
  }

  @Test("a page-appended fill preserves order and updates the count")
  func appendPreservesOrder() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 4, replaceAll: true)
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "C"), doc(4, "D")],
      startPosition: 2, totalCount: 4, replaceAll: false)

    let all = try database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(all.map(\.id) == [1, 2, 3, 4])
    #expect(try database.queryStatus(queryKey: key, serverID: server).totalCount == 4)
  }

  // MARK: - Windowing + deletion gaps

  @Test("the window is by ordered row offset, so deletion gaps are invisible")
  func deletionGapInvisible() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    try database.writeQueryPage(
      queryKey: key, serverID: server,
      documents: (10...14).map { doc($0, "d\($0)") },
      startPosition: 0, totalCount: 5, replaceAll: true)

    // Delete the doc at position 2 — its query_order row cascades away.
    try database.deleteDocuments(serverID: server, removedIDs: [12])

    let window = try database.queryDocuments(queryKey: key, serverID: server, limit: 5)
    #expect(window.map(\.id) == [10, 11, 13, 14])  // gap at position 2 is invisible

    // Offset windows step by ordered row, not by raw position.
    let tail = try database.queryDocuments(queryKey: key, serverID: server, limit: 2, offset: 2)
    #expect(tail.map(\.id) == [13, 14])

    let status = try database.queryStatus(queryKey: key, serverID: server)
    #expect(status.localCount == 4)  // one row gone locally
    #expect(status.totalCount == 5)  // server extent unchanged
  }

  @Test("a delete cascades to every query containing the document")
  func cascadeAcrossQueries() async throws {
    let server = UUID()
    let database = try database(server)
    let keyA = QueryKey(sentinel: "A")
    let keyB = QueryKey(sentinel: "B")

    try database.writeQueryPage(
      queryKey: keyA, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)
    try database.writeQueryPage(
      queryKey: keyB, serverID: server, documents: [doc(2, "B"), doc(3, "C")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    try database.deleteDocuments(serverID: server, removedIDs: [2])

    #expect(
      try database.queryDocuments(queryKey: keyA, serverID: server, limit: 10).map(\.id) == [1])
    #expect(
      try database.queryDocuments(queryKey: keyB, serverID: server, limit: 10).map(\.id) == [3])
  }

  // MARK: - Non-downgrade upsert

  @Test("a Tier-1 upsert does not clobber an existing Tier-2 row")
  func nonDowngradeUpsert() async throws {
    let server = UUID()
    let database = try database(server)

    var detailed = doc(1, "Detail")
    detailed.permissions = Permissions { $0.view = .init(users: [9]) }
    try database.upsertDocument(detailed, serverID: server, projectionLevel: .detail)

    // A later list fill arrives at Tier-1 with no permissions.
    try database.upsertDocuments([doc(1, "Detail")], serverID: server, projectionLevel: .metadata)

    let stored = try record(database, server, 1)
    #expect(stored?.projectionLevel == .detail)
    #expect(stored?.detailFetchedAt != nil)
    #expect(stored?.payload.permissions?.view.users == [9])
  }

  @Test("a Tier-2 upsert upgrades an existing Tier-1 row")
  func upgradeToDetail() async throws {
    let server = UUID()
    let database = try database(server)

    try database.upsertDocuments([doc(1, "Doc")], serverID: server, projectionLevel: .metadata)
    #expect(try record(database, server, 1)?.projectionLevel == .metadata)
    #expect(try record(database, server, 1)?.detailFetchedAt == nil)

    var detailed = doc(1, "Doc")
    detailed.permissions = Permissions { $0.change = .init(groups: [3]) }
    try database.upsertDocument(detailed, serverID: server, projectionLevel: .detail)

    let stored = try record(database, server, 1)
    #expect(stored?.projectionLevel == .detail)
    #expect(stored?.detailFetchedAt != nil)
    #expect(stored?.payload.permissions?.change.groups == [3])
  }

  @Test("a metadata query-page rewrite does not clobber a Tier-2 detail row")
  func queryPageDoesNotDowngradeDetail() async throws {
    // Stage 9 interaction: the proactive fill writes a row at .detail; a later
    // membership/list refresh rewrites that query's order with a .metadata page
    // containing the same id. The order is refreshed but the detail is retained.
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")

    var detailed = doc(1, "Detail")
    detailed.permissions = Permissions { $0.view = .init(users: [9]) }
    try database.upsertDocument(detailed, serverID: server, projectionLevel: .detail)

    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "Detail")],
      startPosition: 0, totalCount: 1, replaceAll: true, projectionLevel: .metadata)

    let stored = try record(database, server, 1)
    #expect(stored?.projectionLevel == .detail)
    #expect(stored?.payload.permissions?.view.users == [9])
  }

  // MARK: - Membership sweep (replaceQueryOrder)

  @Test("replaceQueryOrder skips ids without a document row but counts the server total")
  func replaceQueryOrderSkipsAbsent() async throws {
    // The Tier-0 membership sweep may report ids not yet cached (their detail
    // lands via R3δ). Those are skipped (the FK requires a row); the scrollbar
    // total still reflects the full server count.
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")

    // Only docs 1 and 3 are cached; 2 is reported by the server but absent.
    try database.upsertDocuments(
      [doc(1, "A"), doc(3, "C")], serverID: server, projectionLevel: .detail)

    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1, 2, 3])

    let replayed = try database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(replayed.map(\.id) == [1, 3])  // 2 skipped, order preserved
    let status = try database.queryStatus(queryKey: key, serverID: server)
    #expect(status.totalCount == 3)  // server total, not local count
    #expect(status.localCount == 2)
  }

  @Test("replaceQueryOrder replaces prior membership and preserves the new order")
  func replaceQueryOrderReplaces() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")
    try database.upsertDocuments(
      [doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server, projectionLevel: .metadata)

    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [3, 1])
    #expect(
      try database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [3, 1])

    // A subsequent sweep with a different membership/order fully replaces it.
    try database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [2, 3, 1])
    #expect(
      try database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        2, 3, 1,
      ])
  }

  // MARK: - Order staleness

  @Test("markQueriesOrderStale flips the flag only for queries containing the doc")
  func markOrderStale() async throws {
    let server = UUID()
    let database = try database(server)
    let keyA = QueryKey(sentinel: "A")
    let keyB = QueryKey(sentinel: "B")

    try database.writeQueryPage(
      queryKey: keyA, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try database.writeQueryPage(
      queryKey: keyB, serverID: server, documents: [doc(2, "B")],
      startPosition: 0, totalCount: 1, replaceAll: true)

    #expect(try database.queryStatus(queryKey: keyA, serverID: server).orderStale == false)

    try database.markQueriesOrderStale(containing: 1, serverID: server)

    #expect(try database.queryStatus(queryKey: keyA, serverID: server).orderStale == true)
    #expect(try database.queryStatus(queryKey: keyB, serverID: server).orderStale == false)
  }

  @Test("a fresh fill clears the order-stale flag")
  func fillClearsStale() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try database.markQueriesOrderStale(containing: 1, serverID: server)
    #expect(try database.queryStatus(queryKey: key, serverID: server).orderStale == true)

    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    #expect(try database.queryStatus(queryKey: key, serverID: server).orderStale == false)
  }

  // MARK: - Reconcile support

  @Test("allDocumentIDs returns every cached document id for the server")
  func allDocumentIDs() async throws {
    let server = UUID()
    let database = try database(server)
    try database.upsertDocuments(
      [doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server, projectionLevel: .metadata)

    #expect(try database.allDocumentIDs(serverID: server) == [1, 2, 3])
    // The reconcile diff: local − server.
    let serverIDs: Set<UInt> = [2, 3, 4]
    let removed = try database.allDocumentIDs(serverID: server).subtracting(serverIDs)
    #expect(removed == [1])
  }

  // MARK: - Cache wipe (keeps connections)

  @Test("clearCache wipes document + query rows but keeps the server connection")
  func clearCacheKeepsServer() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    try database.clearCache()

    let counts = try await database.writer.read { db in
      (
        try DocumentRecord.fetchCount(db),
        try QueryOrderRow.fetchCount(db),
        try QueryMetaRow.fetchCount(db)
      )
    }
    #expect(counts == (0, 0, 0))
    // The connection survives the wipe.
    #expect(try database.allConnections().contains { $0.id == server })
  }

  // MARK: - Cascade from server delete

  @Test("removing a connection tears down its document + query_order rows")
  func connectionCascade() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)

    _ = try database.deleteConnection(id: server)

    let counts = try await database.writer.read { db in
      (
        try DocumentRecord.fetchCount(db),
        try QueryOrderRow.fetchCount(db),
        try QueryMetaRow.fetchCount(db)
      )
    }
    #expect(counts == (0, 0, 0))
  }
}
