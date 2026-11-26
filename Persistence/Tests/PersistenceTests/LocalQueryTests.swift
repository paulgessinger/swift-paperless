import Common
import DataModel
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import Persistence

@Suite("Local query evaluation")
struct LocalQueryTests {
  private let server = UUID()

  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  private static let now = day(2026, 6, 15)

  // MARK: - Fixture

  // id  title                              corr  type  path  tags     asn  created     owner
  // 1   Rechnung Telekom März              1     1     1     [1, 2]   10   2026-03-05  1
  // 2   Mietvertrag Wohnung                2     2     -     [2]      20   2019-01-10  1
  // 3   Kontoauszug 2026-05                3     -     -     []       -    2026-05-31  2
  // 4   Überweisung Finanzamt              -     1     2     [3]      40   2025-12-24  -
  // 5   Insurance policy renewal           2     2     1     [1, 3]   -    2026-06-14  1
  private func database() throws -> Persistence.Database {
    func tag(_ id: UInt, _ name: String) -> DataModel.Tag {
      DataModel.Tag(
        id: id, isInboxTag: false, name: name, slug: name.lowercased(),
        color: Color(hex: "#3366cc")!.hex, match: "", matchingAlgorithm: .auto,
        isInsensitive: true, parent: nil)
    }
    func correspondent(_ id: UInt, _ name: String) -> Correspondent {
      Correspondent(
        id: id, name: name, slug: name.lowercased(), matchingAlgorithm: .auto, match: "",
        isInsensitive: true)
    }
    func type(_ id: UInt, _ name: String) -> DocumentType {
      DocumentType(
        id: id, name: name, slug: name.lowercased(), match: "", matchingAlgorithm: .auto,
        isInsensitive: true)
    }
    func path(_ id: UInt, _ name: String) -> StoragePath {
      StoragePath(
        id: id, name: name, path: name, slug: name.lowercased(), matchingAlgorithm: .auto,
        match: "", isInsensitive: true)
    }
    func doc(
      _ id: UInt, _ title: String, correspondent: UInt?, type: UInt?, path: UInt?, tags: [UInt],
      asn: UInt?, created: Date, owner: Owner, pages: Int
    ) -> DataModel.Document {
      DataModel.Document(
        id: id, title: title, asn: asn, documentType: type, correspondent: correspondent,
        created: created, tags: tags, added: created.addingTimeInterval(3600),
        modified: created.addingTimeInterval(7200), originalFileName: "scan-\(id).pdf",
        storagePath: path, owner: owner, pageCount: pages)
    }
    return try Database.seeded(
      serverID: server,
      tags: [tag(1, "Steuer"), tag(2, "Wohnung"), tag(3, "Wichtig")],
      correspondents: [
        correspondent(1, "Telekom"), correspondent(2, "Hausverwaltung Müller"),
        correspondent(3, "Sparkasse"),
      ],
      documentTypes: [type(1, "Rechnung"), type(2, "Vertrag")],
      storagePaths: [path(1, "Archiv"), path(2, "Behörden")],
      documents: [
        doc(
          1, "Rechnung Telekom März", correspondent: 1, type: 1, path: 1, tags: [1, 2], asn: 10,
          created: Self.day(2026, 3, 5), owner: .user(1), pages: 2),
        doc(
          2, "Mietvertrag Wohnung", correspondent: 2, type: 2, path: nil, tags: [2], asn: 20,
          created: Self.day(2019, 1, 10), owner: .user(1), pages: 12),
        doc(
          3, "Kontoauszug 2026-05", correspondent: 3, type: nil, path: nil, tags: [], asn: nil,
          created: Self.day(2026, 5, 31), owner: .user(2), pages: 1),
        doc(
          4, "Überweisung Finanzamt", correspondent: nil, type: 1, path: 2, tags: [3], asn: 40,
          created: Self.day(2025, 12, 24), owner: .none, pages: 3),
        doc(
          5, "Insurance policy renewal", correspondent: 2, type: 2, path: 1, tags: [1, 3],
          asn: nil, created: Self.day(2026, 6, 14), owner: .user(1), pages: 5),
      ])
  }

  /// Give documents a stored, indexed text.
  private func index(_ database: Persistence.Database, _ texts: [UInt: String]) async throws {
    for id in texts.keys {
      try await database.recordFile(
        FileFixtures.key(server, id, .content), documentID: id, size: 10, modified: nil,
        checksum: "c", storedAt: Date(), lastAccessedAt: nil)
    }
    let candidates = try await database.contentAwaitingIndex(limit: 100)
    try await database.indexContent(candidates.map { ($0, texts[$0.documentID]!) })
  }

  private func filter(_ change: (inout FilterState) -> Void = { _ in }) -> FilterState {
    FilterState.empty.with {
      $0.sorting = .init(field: .created, order: .descending)
      $0.searchMode = .titleContent
      change(&$0)
    }
  }

  /// Evaluate and read the stored order back.
  private func evaluate(
    _ database: Persistence.Database, _ filter: FilterState
  ) async throws -> (ids: [UInt], evaluation: LocalEvaluation) {
    let key = QueryKey(serverID: server, filter: filter)
    let evaluation = try #require(
      try await database.evaluateQueryLocally(
        filter: filter, queryKey: key, serverID: server, now: Self.now, calendar: Self.calendar))
    let entries = try await database.queryDocuments(queryKey: key, serverID: server, limit: 100)
    return (entries.map(\.id), evaluation)
  }

  private func ids(_ database: Persistence.Database, _ filter: FilterState) async throws -> [UInt] {
    try await evaluate(database, filter).ids
  }

  // MARK: - Structured filters

  @Test("an empty filter lists every cached document in the sort's order")
  func emptyFilter() async throws {
    let database = try database()
    #expect(try await ids(database, filter()) == [5, 3, 1, 4, 2])
    #expect(
      try await ids(database, filter { $0.sorting = .init(field: .created, order: .ascending) })
        == [2, 4, 1, 3, 5])
  }

  @Test("correspondent, document type, storage path and owner filters")
  func elementFilters() async throws {
    let database = try database()
    #expect(
      try await ids(database, filter { $0.correspondent = .anyOf(ids: [2, 3]) }) == [5, 3, 2])
    #expect(try await ids(database, filter { $0.correspondent = .noneOf(ids: [2]) }) == [3, 1, 4])
    #expect(try await ids(database, filter { $0.correspondent = .notAssigned }) == [4])
    #expect(try await ids(database, filter { $0.documentType = .anyOf(ids: [1]) }) == [1, 4])
    #expect(try await ids(database, filter { $0.documentType = .notAssigned }) == [3])
    #expect(try await ids(database, filter { $0.storagePath = .anyOf(ids: [1]) }) == [5, 1])
    #expect(try await ids(database, filter { $0.storagePath = .notAssigned }) == [3, 2])
    #expect(try await ids(database, filter { $0.owner = .anyOf(ids: [2]) }) == [3])
    #expect(try await ids(database, filter { $0.owner = .notAssigned }) == [4])
    #expect(try await ids(database, filter { $0.owner = .noneOf(ids: [1]) }) == [3, 4])
  }

  @Test("tag filters")
  func tagFilters() async throws {
    let database = try database()
    #expect(try await ids(database, filter { $0.tags = .anyOf(ids: [1, 3]) }) == [5, 1, 4])
    #expect(
      try await ids(database, filter { $0.tags = .allOf(include: [1, 2], exclude: []) }) == [1])
    #expect(
      try await ids(database, filter { $0.tags = .allOf(include: [1], exclude: [2]) }) == [5])
    #expect(
      try await ids(database, filter { $0.tags = .allOf(include: [], exclude: [1, 2]) }) == [3, 4])
    #expect(try await ids(database, filter { $0.tags = .notAssigned }) == [3])
  }

  @Test("ASN filters")
  func asnFilters() async throws {
    let database = try database()
    #expect(try await ids(database, filter { $0.asn = .isNull }) == [5, 3])
    #expect(try await ids(database, filter { $0.asn = .isNotNull }) == [1, 4, 2])
    #expect(try await ids(database, filter { $0.asn = .equalTo(20) }) == [2])
    #expect(try await ids(database, filter { $0.asn = .greaterThan(10) }) == [4, 2])
    #expect(try await ids(database, filter { $0.asn = .lessThan(40) }) == [1, 2])
  }

  @Test("date filters cover whole days and resolve relative ranges")
  func dateFilters() async throws {
    let database = try database()
    #expect(
      try await ids(
        database,
        filter {
          $0.date.created = .between(start: Self.day(2025, 12, 24), end: Self.day(2026, 3, 5))
        }) == [1, 4])
    #expect(
      try await ids(
        database, filter { $0.date.created = .between(start: Self.day(2026, 5, 31), end: nil) })
        == [5, 3])
    #expect(
      try await ids(database, filter { $0.date.created = .range(.currentYear) }) == [5, 3, 1])
    #expect(try await ids(database, filter { $0.date.created = .range(.previousYear) }) == [4])
    #expect(try await ids(database, filter { $0.date.created = .range(.currentMonth) }) == [5])
    #expect(try await ids(database, filter { $0.date.created = .range(.previousMonth) }) == [3])
    #expect(try await ids(database, filter { $0.date.created = .range(.yesterday) }) == [5])
    #expect(
      try await ids(
        database, filter { $0.date.created = .range(.within(num: -1, interval: .month)) })
        == [5, 3])
    #expect(
      try await ids(database, filter { $0.date.added = .range(.within(num: -1, interval: .year)) })
        == [5, 3, 1, 4])
  }

  @Test("filters combine")
  func combinedFilters() async throws {
    let database = try database()
    #expect(
      try await ids(
        database,
        filter {
          $0.correspondent = .anyOf(ids: [2])
          $0.tags = .anyOf(ids: [3])
          $0.date.created = .range(.currentYear)
        }) == [5])
  }

  // MARK: - Sorting

  @Test("sort fields")
  func sorting() async throws {
    let database = try database()
    func sorted(_ field: SortField, _ order: DataModel.SortOrder) async throws -> [UInt] {
      try await ids(database, filter { $0.sorting = .init(field: field, order: order) })
    }
    #expect(try await sorted(.title, .ascending) == [5, 3, 2, 1, 4])
    // Documents without an ASN are last in both directions.
    #expect(try await sorted(.asn, .ascending) == [1, 2, 4, 5, 3])
    #expect(try await sorted(.asn, .descending) == [4, 2, 1, 5, 3])
    // By name: Hausverwaltung Müller (5, 2), Sparkasse (3), Telekom (1), none (4).
    #expect(try await sorted(.correspondent, .ascending) == [5, 2, 3, 1, 4])
    #expect(try await sorted(.documentType, .ascending) == [4, 1, 5, 2, 3])
    #expect(try await sorted(.pageCount, .descending) == [2, 5, 4, 1, 3])
    #expect(try await sorted(.modified, .ascending) == [2, 4, 1, 3, 5])
  }

  @Test("a sort the device can't apply falls back to newest first and is reported")
  func unsupportedSort() async throws {
    let database = try database()
    let result = try await evaluate(
      database, filter { $0.sorting = .init(field: .customField(7), order: .ascending) })
    #expect(result.ids == [5, 3, 1, 4, 2])
    #expect(result.evaluation.limitations == [.sorting])
  }

  // MARK: - Search

  @Test("title search matches substrings, ignoring case and diacritics, every word required")
  func titleSearch() async throws {
    let database = try database()
    func search(_ text: String) async throws -> [UInt] {
      try await ids(
        database,
        filter {
          $0.searchMode = .title
          $0.searchText = text
        })
    }
    #expect(try await search("vertrag") == [2])
    #expect(try await search("UBERWEISUNG") == [4])
    #expect(try await search("märz telekom") == [1])
    #expect(try await search("2026-05") == [3])
    #expect(try await search("telekom wohnung").isEmpty)
    #expect(try await search("   ") == [5, 3, 1, 4, 2])
  }

  @Test("title and content search finds a word in either, per word")
  func titleContentSearch() async throws {
    let database = try database()
    try await index(
      database,
      [
        1: "Ihre Rechnung vom März. Kundennummer 4711. Betrag 39,95 EUR",
        2: "Mietvertrag zwischen Hausverwaltung und Mieter. Kaution 2.400 EUR. zebrafink",
        4: "Bitte überweisen Sie den Betrag an das Finanzamt München",
      ])
    func search(_ text: String) async throws -> (ids: [UInt], evaluation: LocalEvaluation) {
      try await evaluate(database, filter { $0.searchText = text })
    }
    #expect(try await search("zebrafink").ids == [2])
    // "betrag" is only in texts; a prefix of a word matches.
    #expect(try await search("betr").ids == [1, 4])
    // One word from the title, one from the text.
    #expect(try await search("telekom kundennummer").ids == [1])
    #expect(try await search("munchen").ids == [4])
    // Not a prefix of any word, and not in a title.
    #expect(try await search("nummer").ids.isEmpty)
    // Punctuation splits a word into the index's tokens.
    #expect(try await search("39,95").ids == [1])
    // A title match needs no text at all.
    #expect(try await search("insurance").ids == [5])

    let evaluation = try await search("betrag").evaluation
    #expect(evaluation.documents == 5)
    #expect(evaluation.documentsWithText == 3)
    #expect(evaluation.limitations.isEmpty)
  }

  @Test("a filter that doesn't search text reports no text coverage")
  func noCoverageWithoutTextSearch() async throws {
    let database = try database()
    #expect(try await evaluate(database, filter()).evaluation.documentsWithText == nil)
    let title = try await evaluate(
      database,
      filter {
        $0.searchMode = .title
        $0.searchText = "rechnung"
      })
    #expect(title.evaluation.documentsWithText == nil)
  }

  @Test("search combines with the other filters")
  func searchWithFilters() async throws {
    let database = try database()
    try await index(database, [1: "betrag", 4: "betrag"])
    #expect(
      try await ids(
        database,
        filter {
          $0.searchText = "betrag"
          $0.documentType = .anyOf(ids: [1])
          $0.tags = .anyOf(ids: [3])
        }) == [4])
  }

  @Test("advanced search matches names, ASN and file names too, and drops the syntax")
  func advancedSearch() async throws {
    let database = try database()
    try await index(database, [3: "Kontostand zum Monatsende"])
    func search(_ text: String) async throws -> (ids: [UInt], evaluation: LocalEvaluation) {
      try await evaluate(
        database,
        filter {
          $0.searchMode = .advanced
          $0.searchText = text
        })
    }
    // A correspondent's name, which is in neither title nor text.
    #expect(try await search("sparkasse").ids == [3])
    #expect(try await search("müller").ids == [5, 2])
    // A tag's and a document type's name.
    #expect(try await search("wichtig").ids == [5, 4])
    #expect(try await search("vertrag").ids == [5, 2])
    #expect(try await search("40").ids == [4])
    #expect(try await search("scan-3").ids == [3])
    #expect(try await search("kontostand").ids == [3])
    #expect(try await search("kontostand").evaluation.limitations.isEmpty)

    let syntax = try await search("sparkasse AND created:[2020 to 2030] \"kontostand\"")
    #expect(syntax.ids == [3])
    #expect(syntax.evaluation.limitations == [.advancedSyntax])
  }

  @Test("relevance order puts documents with more words in the title first")
  func relevanceOrder() async throws {
    let database = try database()
    try await index(database, [5: "rechnung telekom", 2: "rechnung telekom"])
    let result = try await ids(
      database,
      filter {
        $0.searchText = "rechnung telekom"
        $0.sorting = .init(field: .score, order: .descending)
      })
    #expect(result == [1, 5, 2])
  }

  @Test("filters the device can't apply are left out and reported")
  func limitations() async throws {
    let database = try database()
    let result = try await evaluate(
      database,
      filter {
        $0.duplicates = .with
        $0.remaining = [FilterRule(ruleType: .fulltextMorelike, value: .number(value: 1))!]
      })
    #expect(result.ids.count == 5)
    #expect(result.evaluation.limitations == [.duplicates, .otherRules])
  }

  // MARK: - The stored order

  @Test("the order is marked local, never complete, and counts its documents")
  func marksOrder() async throws {
    let database = try database()
    let filter = filter { $0.tags = .anyOf(ids: [1]) }
    let key = QueryKey(serverID: server, filter: filter)
    _ = try await evaluate(database, filter)

    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.totalCount == 2)
    #expect(status.localCount == 2)
    #expect(!status.isComplete)
    #expect(!status.orderStale)
    #expect(status.localEvaluation?.documents == 5)
    #expect(status.localEvaluation?.evaluatedAt == Self.now)
  }

  @Test("evaluating again replaces the order")
  func reevaluates() async throws {
    let database = try database()
    let filter = filter { $0.tags = .anyOf(ids: [1]) }
    #expect(try await ids(database, filter) == [5, 1])
    try await database.deleteDocuments(serverID: server, removedIDs: [5])
    #expect(try await ids(database, filter) == [1])
  }

  @Test("an empty answer is stored as an empty, local order")
  func emptyAnswer() async throws {
    let database = try database()
    let filter = filter { $0.asn = .equalTo(999) }
    let key = QueryKey(serverID: server, filter: filter)
    #expect(try await ids(database, filter).isEmpty)
    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.totalCount == 0)
    #expect(status.localEvaluation != nil)
  }

  @Test("the server's first page replaces a local order and clears the mark")
  func serverPageClearsMark() async throws {
    let database = try database()
    let filter = filter { $0.tags = .anyOf(ids: [1]) }
    let key = QueryKey(serverID: server, filter: filter)
    _ = try await evaluate(database, filter)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    let page = [FileFixtures.doc(2), FileFixtures.doc(1)]
    #expect(
      try await database.replaceQueryPage(
        queryKey: key, serverID: server, documents: page, totalCount: 2, basis: basis))

    let status = try await database.queryStatus(queryKey: key, serverID: server)
    #expect(status.localEvaluation == nil)
    let entries = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(entries.map(\.id) == [2, 1])
  }

  @Test("asked only if unanswered, the device leaves the server's rows alone")
  func onlyIfUnanswered() async throws {
    let database = try database()
    let filter = filter { $0.tags = .anyOf(ids: [1]) }
    let key = QueryKey(serverID: server, filter: filter)
    func evaluate() async throws -> LocalEvaluation? {
      try await database.evaluateQueryLocally(
        filter: filter, queryKey: key, serverID: server, onlyIfUnanswered: true)
    }

    // Nothing cached: answered.
    #expect(try await evaluate() != nil)
    // Its own earlier answer: answered again.
    #expect(try await evaluate() != nil)

    // The server's first page landed meanwhile: held back, rows untouched.
    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.replaceQueryPage(
      queryKey: key, serverID: server, documents: [FileFixtures.doc(2)], totalCount: 1,
      basis: basis)
    #expect(try await evaluate() == nil)
    let entries = try await database.queryDocuments(queryKey: key, serverID: server, limit: 10)
    #expect(entries.map(\.id) == [2])
    #expect(try await database.queryStatus(queryKey: key, serverID: server).localEvaluation == nil)
  }

  @Test("a membership rewrite clears the mark too")
  func membershipRewriteClearsMark() async throws {
    let database = try database()
    let filter = filter()
    let key = QueryKey(serverID: server, filter: filter)
    _ = try await evaluate(database, filter)

    let basis = try await database.queryWriteBasis(queryKey: key, serverID: server)
    try await database.replaceQueryOrder(
      queryKey: key, serverID: server, orderedIDs: [3, 1], basis: basis)

    #expect(try await database.queryStatus(queryKey: key, serverID: server).localEvaluation == nil)
  }

  @Test("another server's documents and texts stay out")
  func scopedToServer() async throws {
    let database = try database()
    let other = UUID()
    try FileFixtures.addServer(other, to: database)
    try await database.upsertDocuments(
      [
        DataModel.Document(
          id: 1, title: "Rechnung zebrafink", created: Self.day(2026, 1, 1), tags: [],
          owner: .user(1))
      ], serverID: other)
    try await database.recordFile(
      FileFixtures.key(other, 1, .content), documentID: 1, size: 1, modified: nil,
      checksum: "c", storedAt: Date(), lastAccessedAt: nil)
    let candidates = try await database.contentAwaitingIndex(limit: 10)
    try await database.indexContent(candidates.map { ($0, "kolibri") })

    #expect(try await ids(database, filter { $0.searchText = "zebrafink" }).isEmpty)
    #expect(try await ids(database, filter { $0.searchText = "kolibri" }).isEmpty)
    #expect(try await ids(database, filter()).count == 5)
  }

  @Test("a large library is evaluated in one statement")
  func largeLibrary() async throws {
    let database = try Database.seeded(serverID: server)
    let count = 20_000
    try await database.upsertDocuments(
      (1...count).map {
        DataModel.Document(
          id: UInt($0), title: $0 % 100 == 0 ? "Rechnung \($0)" : "Dokument \($0)",
          correspondent: UInt($0 % 50),
          created: Date(timeIntervalSinceReferenceDate: Double($0) * 3600),
          tags: [UInt($0 % 7), UInt($0 % 11)], owner: .user(1))
      }, serverID: server)

    let result = try await evaluate(
      database,
      filter {
        $0.searchMode = .title
        $0.searchText = "rechnung"
        $0.tags = .anyOf(ids: [0])
      })
    // Every 100th document, of which those with id % 7 == 0 or id % 11 == 0.
    let expected = stride(from: 100, through: count, by: 100).filter {
      $0 % 7 == 0 || $0 % 11 == 0
    }
    #expect(result.ids.count == min(expected.count, 100))
    #expect(result.evaluation.documents == count)
    let key = QueryKey(
      serverID: server,
      filter: filter {
        $0.searchMode = .title
        $0.searchText = "rechnung"
        $0.tags = .anyOf(ids: [0])
      })
    #expect(
      try await database.queryStatus(queryKey: key, serverID: server).totalCount
        == UInt(expected.count))

    // The whole library, to see the write scale.
    #expect(try await evaluate(database, filter()).evaluation.documents == count)
    let all = QueryKey(serverID: server, filter: filter())
    #expect(
      try await database.queryStatus(queryKey: all, serverID: server).localCount == count)
  }
}

@Suite("Local search text")
struct LocalSearchTextTests {
  @Test("words are folded and split on whitespace")
  func words() {
    #expect(
      LocalSearchText.words("  Überweisung  MÄRZ\t2024-07 ") == ["uberweisung", "marz", "2024-07"])
    #expect(LocalSearchText.words("").isEmpty)
  }

  @Test("a word's tokens are its runs of letters and digits")
  func tokens() {
    #expect(LocalSearchText.tokens("2024-07") == ["2024", "07"])
    #expect(LocalSearchText.tokens("quittungsnummer-7781") == ["quittungsnummer", "7781"])
    #expect(LocalSearchText.tokens("--").isEmpty)
  }

  @Test("the match expression requires every token, as a prefix unless one character")
  func matchExpression() {
    #expect(LocalSearchText.matchExpression("rechn") == "\"rechn\"*")
    #expect(LocalSearchText.matchExpression("2024-07") == "\"2024\"* AND \"07\"*")
    #expect(LocalSearchText.matchExpression("a") == "\"a\"")
    #expect(LocalSearchText.matchExpression("§") == nil)
  }

  @Test("advanced words drop field terms and operators")
  func advancedWords() {
    let plain = LocalSearchText.advancedWords("Rechnung telekom")
    #expect(plain.words == ["rechnung", "telekom"])
    #expect(!plain.simplified)

    let syntax = LocalSearchText.advancedWords(
      "rechnung AND tag:steuer created:[-3 month to now],\"Telekom\" foo*")
    #expect(syntax.words == ["rechnung", "telekom", "foo"])
    #expect(syntax.simplified)
  }
}
