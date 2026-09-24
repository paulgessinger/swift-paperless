import DataModel
import Foundation
import GRDB
import Testing

@testable import Persistence

/// The changed-documents delta (R3δ) marks cached query orders stale when a
/// refresh may have moved a document within them or out of them
/// (`Database.applyChangedDocuments`).
@Suite("DeltaOrderStaleness", .bug("https://github.com/paulgessinger/swift-paperless/issues/689"))
struct DeltaOrderStalenessTests {
  // Fractional seconds on purpose: the comparison runs against a row read back
  // from disk, so a date that didn't survive the round trip exactly would make
  // every identical refresh look like a change.
  private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t + 0.123_456) }

  private func doc(_ id: UInt, _ title: String = "Doc", modified: TimeInterval = 3000) -> Document {
    var document = Document(
      id: id, title: title, asn: id, documentType: 2, correspondent: 3,
      created: date(1000), tags: [4, 5], added: date(2000), modified: date(modified),
      originalFileName: "scan.pdf", archivedFileName: "archive.pdf", storagePath: 6,
      owner: .user(7), pageCount: 3, notes: NotesPayload(count: 1))
    document.permissions = Permissions { $0.view = .init(users: [1, 2]) }
    return document
  }

  private func database(_ server: UUID) throws -> Persistence.Database {
    try Database.seeded(serverID: server)
  }

  private func fill(
    _ database: Persistence.Database, _ server: UUID, _ key: QueryKey, _ documents: [Document]
  ) async throws {
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: documents,
      startPosition: 0, totalCount: UInt(documents.count), replaceAll: true)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)
  }

  private func isStale(
    _ database: Persistence.Database, _ server: UUID, _ key: QueryKey
  ) async throws -> Bool {
    try await database.queryStatus(queryKey: key, serverID: server).orderStale
  }

  @Test("An identical refresh marks nothing")
  func identicalRefresh() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "list")
    try await fill(database, server, key, [doc(1), doc(2)])

    // What the delta's day-granular re-fetch hands back most of the time.
    let marked = try await database.applyChangedDocuments([doc(1), doc(2)], serverID: server)

    #expect(marked == 0)
    #expect(try await isStale(database, server, key) == false)
  }

  @Test("A changed modified date marks every list containing the document, and only those")
  func relevantChange() async throws {
    let server = UUID()
    let database = try database(server)
    let byTitle = QueryKey(sentinel: "by-title")
    let inbox = QueryKey(sentinel: "inbox")
    let other = QueryKey(sentinel: "other")
    try await fill(database, server, byTitle, [doc(1), doc(2)])
    try await fill(database, server, inbox, [doc(1)])
    try await fill(database, server, other, [doc(2)])

    let marked = try await database.applyChangedDocuments(
      [doc(1, "Renamed", modified: 4000)], serverID: server)

    #expect(marked == 2)
    #expect(try await isStale(database, server, byTitle))
    #expect(try await isStale(database, server, inbox))
    #expect(try await isStale(database, server, other) == false)
    #expect(try await database.document(serverID: server, id: 1)?.title == "Renamed")
  }

  @Test("A refresh that leaves modified alone marks nothing")
  func unchangedModified() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "list")
    try await fill(database, server, key, [doc(1)])

    var changed = doc(1)
    changed.archivedFileName = "renamed-archive.pdf"
    let marked = try await database.applyChangedDocuments([changed], serverID: server)

    #expect(marked == 0)
    #expect(try await isStale(database, server, key) == false)
  }

  @Test("A document listed nowhere marks nothing, entering a list is left to its refill")
  func unlistedDocument() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "list")
    try await fill(database, server, key, [doc(1)])
    try await database.upsertDocuments([doc(2)], serverID: server)

    let marked = try await database.applyChangedDocuments(
      [doc(2, "Now matches", modified: 4000), doc(3, "Brand new")], serverID: server)

    #expect(marked == 0)
    #expect(try await isStale(database, server, key) == false)
  }

  @Test("A skeleton's arriving object marks its list: there was nothing to compare")
  func skeletonArrives() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "view")
    try await database.upsertDocuments([doc(1)], serverID: server)
    // The membership sweep lists ids before their objects are cached.
    try await database.replaceQueryOrder(queryKey: key, serverID: server, orderedIDs: [1, 2])

    let marked = try await database.applyChangedDocuments([doc(2)], serverID: server)

    #expect(marked == 1)
    #expect(try await isStale(database, server, key))
  }

  @Test("A list already marked isn't counted again")
  func alreadyStale() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "list")
    try await fill(database, server, key, [doc(1)])
    try await database.markQueriesOrderStale(containing: 1, serverID: server)

    let marked = try await database.applyChangedDocuments(
      [doc(1, "Renamed", modified: 4000)], serverID: server)

    #expect(marked == 0)
    #expect(try await isStale(database, server, key))
  }

  @Test("A mark landing mid-fill survives the fill's remaining pages")
  func markDuringFill() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "list")

    // Page 1 places document 1, the delta then moves it, and page 2 appends
    // behind it without revisiting page 1's rows.
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(1)],
      startPosition: 0, totalCount: 2, replaceAll: true)
    try await database.applyChangedDocuments(
      [doc(1, "Renamed", modified: 4000)], serverID: server)
    try await database.writeQueryPage(
      queryKey: key, serverID: server, documents: [doc(2)],
      startPosition: 1, totalCount: 2, replaceAll: false)
    try await database.markQueryFillComplete(queryKey: key, serverID: server)

    #expect(try await isStale(database, server, key))
    // The fill finished, so the order is complete — complete but not current.
    #expect(try await database.queryStatus(queryKey: key, serverID: server).isComplete)
  }

  @Test("The next whole-order rewrite clears the mark")
  func refillClears() async throws {
    let server = UUID()
    let database = try database(server)
    let key = QueryKey(sentinel: "list")
    try await fill(database, server, key, [doc(1), doc(2)])
    try await database.applyChangedDocuments(
      [doc(1, "Zzz", modified: 4000)], serverID: server)

    try await fill(database, server, key, [doc(2), doc(1, "Zzz", modified: 4000)])

    #expect(try await isStale(database, server, key) == false)
  }

  @Test("Marking is scoped to the refreshed server")
  func serverScoping() async throws {
    let serverA = UUID()
    let serverB = UUID()
    let database = try database(serverA)
    try database.upsertConnection(
      ConnectionRecord(
        id: serverB,
        url: URL(string: "https://other.example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "bob")))
    let key = QueryKey(sentinel: "list")
    try await fill(database, serverA, key, [doc(1)])
    try await fill(database, serverB, key, [doc(1)])

    try await database.applyChangedDocuments(
      [doc(1, "Renamed", modified: 4000)], serverID: serverA)

    #expect(try await isStale(database, serverA, key))
    #expect(try await isStale(database, serverB, key) == false)
  }
}
