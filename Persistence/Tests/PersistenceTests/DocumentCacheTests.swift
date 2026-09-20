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

    try await database.upsertDocument(input, serverID: server)
    let output = try await database.document(serverID: server, id: 1)

    #expect(output == input)
    #expect(output?.currentVersionID == 9)  // newest by `added`
    #expect(output?.rootVersionID == 1)
  }

  @Test("document(asn:) resolves via the indexed column")
  func resolvesByAsn() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [doc(1, "A", asn: 100), doc(2, "B", asn: 200)],
      serverID: server)

    #expect(try await database.document(serverID: server, asn: 200)?.id == 2)
    #expect(try await database.document(serverID: server, asn: 999) == nil)
  }

  // MARK: - query_order replay

  @Test("queryDocuments replays the server order, not id/sort order")
  func replaysServerOrder() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    // Written out of natural id order.
    try await database.writeQueryPage(
      queryKey: key, serverID: server,
      documents: [doc(3, "C"), doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 3, replaceAll: true)

    let replayed = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(replayed.map(\.id) == [3, 1, 2])
  }

  @Test("a page-appended fill preserves order and updates the count")
  func appendPreservesOrder() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 4, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "C"), doc(4, "D")],
      startPosition: 2, totalCount: 4, replaceAll: false)

    let all = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(all.map(\.id) == [1, 2, 3, 4])
    #expect(try await database.queryStatus(queryKey: key, serverID: server).totalCount == 4)
  }

  @Test("a document repeated across a page boundary is placed only once")
  func overlappingPageDoesNotDuplicate() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B"), doc(3, "C")],
      startPosition: 0, totalCount: 4, replaceAll: true)
    // Page 2 re-delivers doc 3, as it does when the page offsets shift.
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "C"), doc(4, "D")],
      startPosition: 3, totalCount: 4, replaceAll: false)

    let all = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(all.map(\.id) == [1, 2, 3, 4])
    // A duplicate would inflate `localCount` as well as duplicating the row.
    #expect(try await database.queryStatus(queryKey: key, serverID: server).localCount == 4)
  }

  @Test("a second writer on the same position overwrites instead of throwing")
  func positionCollisionDoesNotAbort() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)
    // A concurrent fill lands on the same positions with different documents.
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "C"), doc(4, "D")],
      startPosition: 0, totalCount: 2, replaceAll: false)

    // The later write wins, as it did when this used `upsert`.
    let all = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(all.map(\.id) == [3, 4])
  }

  @Test("uniqueness is per query, so a document can sit in several lists")
  func uniquenessIsScopedToTheQuery() async throws {
    let server = UUID()
    let database = try database(server)
    let a = QueryKey(sentinel: "a")
    let b = QueryKey(sentinel: "b")

    try await database.writeQueryPage(
      queryKey: a, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: b, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)

    #expect(
      try await database.queryDocuments(queryKey: a, serverID: server, limit: 10).map(\.id) == [1])
    #expect(
      try await database.queryDocuments(queryKey: b, serverID: server, limit: 10).map(\.id) == [1])
  }

  // MARK: - Windowing + deletion gaps

  @Test("the window is by ordered row offset, so deletion gaps are invisible")
  func deletionGapInvisible() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "test")

    try await database.writeQueryPage(
      queryKey: key, serverID: server,
      documents: (10...14).map { doc($0, "d\($0)") },
      startPosition: 0, totalCount: 5, replaceAll: true)

    // Delete the doc at position 2 — its query_order row cascades away.
    try await database.deleteDocuments(serverID: server, removedIDs: [12])

    let window = try await database.queryDocuments(queryKey: key, serverID: server, limit: 5)
    #expect(window.map(\.id) == [10, 11, 13, 14])  // gap at position 2 is invisible

    // Offset windows step by ordered row, not by raw position.
    let tail = try await database.queryDocuments(
      queryKey: key, serverID: server, limit: 2, offset: 2)
    #expect(tail.map(\.id) == [13, 14])

    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.localCount == 4)  // one row gone locally
    #expect(status.totalCount == 5)  // server extent unchanged
  }

  @Test("a delete cascades to every query containing the document")
  func cascadeAcrossQueries() async throws {
    let server = UUID()
    let database = try database(server)
    let keyA = QueryKey(sentinel: "A")
    let keyB = QueryKey(sentinel: "B")

    try await database.writeQueryPage(
      queryKey: keyA, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: keyB, serverID: server, documents: [doc(2, "B"), doc(3, "C")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    try await database.deleteDocuments(serverID: server, removedIDs: [2])

    #expect(
      try await database.queryDocuments(queryKey: keyA, serverID: server, limit: 10).map(\.id) == [
        1
      ])
    #expect(
      try await database.queryDocuments(queryKey: keyB, serverID: server, limit: 10).map(\.id) == [
        3
      ])
  }

  // MARK: - Upsert

  @Test("an upsert replaces an existing row outright")
  func upsertReplaces() async throws {
    // No projection level: every stored row is the complete object (the list
    // carries full_perms), so a later upsert just replaces the row, permissions
    // and all.
    let server = UUID()
    let database = try database(server)

    var first = doc(1, "Doc")
    first.permissions = Permissions { $0.view = .init(users: [9]) }
    try await database.upsertDocument(first, serverID: server)

    var second = doc(1, "Doc")
    second.permissions = Permissions { $0.view = .init(users: [42]) }
    try await database.upsertDocument(second, serverID: server)

    #expect(try record(database, server, 1)?.payload.permissions?.view.users == [42])
  }

  // MARK: - Membership sweep (replaceQueryOrder)

  @Test("replaceQueryOrder writes all ids; absent objects read back as skeletons")
  func replaceQueryOrderWritesSkeletons() async throws {
    // The Tier-0 membership sweep may report ids not yet cached (their object
    // lands via R3δ). They are written to query_order regardless (no FK to
    // document) and read back as skeleton entries, in order.
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")

    // Only docs 1 and 3 are cached; 2 is reported by the server but absent.
    try await database.upsertDocuments([doc(1, "A"), doc(3, "C")], serverID: server)

    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1, 2, 3])

    let replayed = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(replayed.map(\.id) == [1, 2, 3])  // all ids, order preserved
    #expect(replayed[0].document != nil)  // loaded
    #expect(replayed[1].document == nil)  // id 2 is a skeleton
    #expect(replayed[2].document != nil)  // loaded
    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.totalCount == 3)
  }

  @Test("replaceQueryOrder replaces prior membership and preserves the new order")
  func replaceQueryOrderReplaces() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")
    try await database.upsertDocuments(
      [doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)

    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [3, 1])
    #expect(
      try await database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        3, 1,
      ])

    // A subsequent sweep with a different membership/order fully replaces it.
    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [2, 3, 1])
    #expect(
      try await database.queryDocuments(queryKey: key, serverID: server, limit: 10).map(\.id) == [
        2, 3, 1,
      ])
  }

  // MARK: - Fill completion

  @Test("a fill is not complete until it says so, and page 1 un-completes the key")
  func fillCompletionStamp() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "fill")

    // Page 1 truncated the key's order down to what it just wrote, so the key
    // is incomplete no matter what it was before.
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 4, replaceAll: true)
    #expect(try await database.queryFillCompletedAt(queryKey: key, serverID: server) == nil)

    // An appended page is still not a completed fill — this is the case that
    // used to be indistinguishable from one.
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(2, "B")],
      startPosition: 1, totalCount: 4, replaceAll: false)
    #expect(try await database.queryFillCompletedAt(queryKey: key, serverID: server) == nil)

    try await database.markQueryFillComplete(queryKey: key, serverID: server)
    #expect(try await database.queryFillCompletedAt(queryKey: key, serverID: server) != nil)

    // A new fill's page 1 wipes the order, so the completion goes with it.
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(3, "C")],
      startPosition: 0, totalCount: 9, replaceAll: true)
    #expect(try await database.queryFillCompletedAt(queryKey: key, serverID: server) == nil)
  }

  @Test("marking a fill complete keeps the recorded total and stale flag")
  func fillCompletionPreservesMeta() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "fill")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 7, replaceAll: true)
    try await database.markQueriesOrderStale(containing: 1, serverID: server)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)

    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.totalCount == 7)
    #expect(status.orderStale)
  }

  @Test("a membership rewrite leaves the completion stamp alone")
  func replaceQueryOrderKeepsFillStamp() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")
    try await database.upsertDocuments([doc(1, "A"), doc(2, "B")], serverID: server)

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)
    let stamped = try #require(
      try await database.queryFillCompletedAt(queryKey: key, serverID: server))

    // The sweep writes a complete ordering of its own, so it neither claims nor
    // revokes the fill's completion.
    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [2, 1])
    #expect(try await database.queryFillCompletedAt(queryKey: key, serverID: server) == stamped)
  }

  // MARK: - Order staleness

  @Test("markQueriesOrderStale flips the flag only for queries containing the doc")
  func markOrderStale() async throws {
    let server = UUID()
    let database = try database(server)
    let keyA = QueryKey(sentinel: "A")
    let keyB = QueryKey(sentinel: "B")

    try await database.writeQueryPage(
      queryKey: keyA, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: keyB, serverID: server, documents: [doc(2, "B")],
      startPosition: 0, totalCount: 1, replaceAll: true)

    #expect(try await database.queryStatus(queryKey: keyA, serverID: server).orderStale == false)

    try await database.markQueriesOrderStale(containing: 1, serverID: server)

    #expect(try await database.queryStatus(queryKey: keyA, serverID: server).orderStale == true)
    #expect(try await database.queryStatus(queryKey: keyB, serverID: server).orderStale == false)
  }

  @Test("a fresh fill clears the order-stale flag")
  func fillClearsStale() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.markQueriesOrderStale(containing: 1, serverID: server)
    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale == true)

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale == false)
  }

  @Test(
    "an appended page keeps a stale flag set after page 1",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/689"))
  func appendKeepsStale() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 2, replaceAll: true)
    // A refresh moved document 1 after page 1 placed it; page 2 doesn't
    // revisit page 1's rows, so it can't vouch for them.
    try await database.markQueriesOrderStale(containing: 1, serverID: server)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(2, "B")],
      startPosition: 1, totalCount: 2, replaceAll: false)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale)
  }

  @Test("an appended page leaves a clean order clean")
  func appendKeepsClean() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 2, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(2, "B")],
      startPosition: 1, totalCount: 2, replaceAll: false)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale == false)
  }

  @Test("a membership rewrite clears the order-stale flag")
  func membershipRewriteClearsStale() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")

    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)
    try await database.markQueriesOrderStale(containing: 1, serverID: server)

    // The server's own ordering of the whole key, so it is current again.
    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [2, 1])
    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale == false)
  }

  // MARK: - Marks landing mid-rewrite

  /// A whole-order rewrite asks the server for the list's answer, waits, and
  /// then writes it and clears the stale flag. These cover the window in
  /// between: a mark landing there describes a change the answer in hand
  /// predates, and nothing re-marks the key afterwards, so clearing over it
  /// leaves the list wrong until some other document in it changes.

  @Test(
    "a mark landing while a membership rewrite is in flight survives it",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/689"))
  func markDuringMembershipRewriteSurvives() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    // The request goes out with the counter as it stands…
    let generation = try await database.queryOrderGeneration(queryKey: key, serverID: server)
    // …document 2 changes while the server is answering…
    try await database.markQueriesOrderStale(containing: 2, serverID: server)
    // …and the answer, which predates that change, lands.
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [2, 1], clearingStaleIf: generation)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale)
  }

  @Test("an uncontested membership rewrite still clears the flag")
  func uncontestedMembershipRewriteClears() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    // The mark is what triggered the rewrite, so it is accounted for by the
    // answer the rewrite asked for.
    try await database.markQueriesOrderStale(containing: 1, serverID: server)
    let generation = try await database.queryOrderGeneration(queryKey: key, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [2, 1], clearingStaleIf: generation)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale == false)
  }

  @Test(
    "a mark landing while a fill's first page is in flight survives it",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/689"))
  func markDuringFirstPageSurvives() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    let generation = try await database.queryOrderGeneration(queryKey: key, serverID: server)
    try await database.markQueriesOrderStale(containing: 2, serverID: server)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(2, "B"), doc(1, "A")],
      startPosition: 0, totalCount: 2, replaceAll: true, clearingStaleIf: generation)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale)
  }

  @Test("an uncontested first page still clears the flag")
  func uncontestedFirstPageClears() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.markQueriesOrderStale(containing: 1, serverID: server)

    let generation = try await database.queryOrderGeneration(queryKey: key, serverID: server)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true, clearingStaleIf: generation)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale == false)
  }

  @Test("a mark on an already-stale list still advances its counter")
  func markAdvancesCounterWhenAlreadyStale() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    // The flag is already set — which is the normal state when the list on
    // screen reacts to it — so a second mark has no flag left to flip. It must
    // still be visible to a rewrite already in flight.
    try await database.markQueriesOrderStale(containing: 1, serverID: server)
    let generation = try await database.queryOrderGeneration(queryKey: key, serverID: server)
    try await database.markQueriesOrderStale(containing: 2, serverID: server)

    #expect(
      try await database.queryOrderGeneration(queryKey: key, serverID: server) != generation)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [2, 1], clearingStaleIf: generation)
    #expect(try await database.queryStatus(queryKey: key, serverID: server).orderStale)
  }

  @Test("the counter is per key: a mark on another list doesn't hold up a rewrite")
  func counterIsPerKey() async throws {
    let server = UUID()
    let database = try database(server)
    let keyA = QueryKey(sentinel: "A")
    let keyB = QueryKey(sentinel: "B")
    try await database.writeQueryPage(
      queryKey: keyA, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.writeQueryPage(
      queryKey: keyB, serverID: server, documents: [doc(2, "B")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.markQueriesOrderStale(containing: 1, serverID: server)

    let generation = try await database.queryOrderGeneration(queryKey: keyA, serverID: server)
    // Only B's member changes while A's rewrite is in flight.
    try await database.markQueriesOrderStale(containing: 2, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: keyA, serverID: server, orderedIDs: [1], clearingStaleIf: generation)

    #expect(try await database.queryStatus(queryKey: keyA, serverID: server).orderStale == false)
    #expect(try await database.queryStatus(queryKey: keyB, serverID: server).orderStale)
  }

  @Test("a rewrite's own write doesn't move the counter")
  func rewriteLeavesCounterAlone() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 0, totalCount: 1, replaceAll: true)
    try await database.markQueriesOrderStale(containing: 1, serverID: server)

    // A `query_meta` upsert rewrites every column, so the counter has to be
    // carried forward: losing it would make the *next* capture compare against
    // a reset value and clear over a mark it never saw.
    let generation = try await database.queryOrderGeneration(queryKey: key, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [1], clearingStaleIf: generation)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A")],
      startPosition: 1, totalCount: 2, replaceAll: false)

    #expect(try await database.queryOrderGeneration(queryKey: key, serverID: server) == generation)
  }

  // MARK: - Reconcile support

  @Test("allDocumentIDs returns every cached document id for the server")
  func allDocumentIDs() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)

    #expect(try await database.allDocumentIDs(serverID: server) == [1, 2, 3])
    // The reconcile diff: local − server.
    let serverIDs: Set<UInt> = [2, 3, 4]
    let removed = try await database.allDocumentIDs(serverID: server).subtracting(serverIDs)
    #expect(removed == [1])
  }

  @Test("documentIDsWithoutRows keeps the caller's order and drops repeats")
  func documentIDsWithoutRows() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments([doc(2, "B"), doc(4, "D")], serverID: server)

    // The ids a membership rewrite would write as skeletons, top of the list
    // first — which is the order a bounded hydration fetches them in.
    #expect(
      try await database.documentIDsWithoutRows(serverID: server, among: [1, 2, 3, 4, 5, 3])
        == [1, 3, 5])
    #expect(try await database.documentIDsWithoutRows(serverID: server, among: [2, 4]) == [])
    #expect(try await database.documentIDsWithoutRows(serverID: server, among: []) == [])
  }

  @Test("documentIDsWithoutRows doesn't count another server's rows as cached")
  func documentIDsWithoutRowsIsPerServer() async throws {
    let server = UUID()
    let other = UUID()
    let database = try database(server)
    try database.upsertConnection(
      ConnectionRecord(
        id: other,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))
    try await database.upsertDocuments([doc(1, "A")], serverID: other)

    #expect(try await database.documentIDsWithoutRows(serverID: server, among: [1]) == [1])
  }

  // MARK: - Diagnostics (cached document count)

  @Test("documentCount reflects the number of cached document rows for a server")
  func documentCountReflectsRows() async throws {
    let server = UUID()
    let database = try database(server)

    #expect(try await database.documentCount(serverID: server) == 0)

    try await database.upsertDocuments([doc(1, "A"), doc(2, "B"), doc(3, "C")], serverID: server)
    #expect(try await database.documentCount(serverID: server) == 3)

    try await database.deleteDocuments(serverID: server, removedIDs: [2])
    #expect(try await database.documentCount(serverID: server) == 2)
  }

  // MARK: - Cache wipe (keeps connections)

  @Test("clearCache wipes document + query rows but keeps the server connection")
  func clearCacheKeepsServer() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "A")
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1, "A"), doc(2, "B")],
      startPosition: 0, totalCount: 2, replaceAll: true)

    try await database.clearCache()

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
    try await database.writeQueryPage(
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

  // MARK: - Blob reachability (ContentStore reclaim)

  private func versioned(_ id: UInt, versions: [UInt]) -> Document {
    Document(
      id: id, title: "v", created: date(1000), tags: [], owner: .user(1),
      versions: versions.map {
        DocumentVersion(id: $0, added: date(1000), isRoot: $0 == versions.first)
      })
  }

  @Test("retainedContentVersions reports only the current version of each document")
  func retainedVersionsAreCurrentOnly() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [
        versioned(1, versions: [1, 9]),  // 1 is superseded by 9
        doc(2, "no versions"),  // falls back to the document id
      ], serverID: server)

    let retained = try await database.retainedContentVersions()

    #expect(retained == [server: [9, 2]])
  }

  @Test("retainedContentVersions spans every server in one answer")
  func retainedVersionsSpanServers() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "b")))
    try await database.upsertDocuments([doc(1, "A")], serverID: serverA)
    try await database.upsertDocuments([doc(1, "B")], serverID: serverB)

    let retained = try await database.retainedContentVersions()

    // Same document id on both servers: the blob store is shared, so the answer
    // has to stay keyed by server.
    #expect(retained == [serverA: [1], serverB: [1]])
  }

  @Test("a deleted document stops retaining its content")
  func deletedDocumentReleasesContent() async throws {
    let server = UUID()
    let database = try database(server)
    try await database.upsertDocuments(
      [versioned(1, versions: [1, 9]), doc(2, "B")], serverID: server)

    try await database.deleteDocuments(serverID: server, removedIDs: [1])

    #expect(try await database.retainedContentVersions() == [server: [2]])
  }
}
