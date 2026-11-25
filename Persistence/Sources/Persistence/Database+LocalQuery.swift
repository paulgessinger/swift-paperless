import DataModel
import Foundation
import GRDB

/// Answering a document list on the device.
///
/// A cached list is normally the server's answer, replayed (see
/// `V4_CreateDocumentCache`). When the server can't be asked and nothing is
/// cached for a query, ``Database/evaluateQueryLocally(filter:queryKey:serverID:now:calendar:)``
/// answers it from what the device holds instead: the filter is applied to the
/// cached `document` rows, a text search to their titles and to the full-text
/// index over the stored texts (`Database+SearchIndex`), and the result is
/// written as the query's order like a fill would write it. The list observes
/// it the same way and needs no second read path.
///
/// The order is marked with a ``LocalEvaluation`` (`query_meta.local_evaluation`),
/// and never stamped as filled, so every later fill still runs. The first
/// server write to the key (page 1 of a fill, or a membership rewrite) replaces
/// the order and clears the mark.
///
/// It is an approximation by design. The server's search engine is not
/// reimplemented: words are matched as substrings of the title and as word
/// prefixes in the text, all of them required. Filters the cached rows can't
/// answer are left out and named in the evaluation.
///
/// Async only, like every cache table — see the rule in `Database+Connections`.
extension Database {
  /// Answer `filter` from the device and store the result as `queryKey`'s
  /// order, replacing what was cached for it.
  ///
  /// The caller owns the key while this runs, like any other writer of a
  /// query's order (`KeyOwnership` in `CachingRepository`).
  @discardableResult
  public func evaluateQueryLocally(
    filter: FilterState, queryKey: QueryKey, serverID: UUID,
    now: Date = Date(), calendar: Calendar = .current
  ) async throws -> LocalEvaluation {
    try await wrappingAsync("evaluateQueryLocally") {
      try await writer.write { db in
        let plan = try LocalQueryPlan(
          db, filter: filter, serverID: serverID, now: now, calendar: calendar)

        try Self.deleteQueryOrder(db, queryKey: queryKey, serverID: serverID)
        var arguments: StatementArguments = [queryKey.rawValue]
        arguments += plan.orderArguments
        arguments += [serverID]
        arguments += plan.conditionArguments
        try db.execute(
          sql: """
            INSERT INTO query_order (server_id, query_key, position, remote_id, placed_modified)
            SELECT d.server_id, ?, ROW_NUMBER() OVER (ORDER BY \(plan.order)) - 1, d.id, d.modified
            FROM document d
            WHERE d.server_id = ?\(plan.conditions.map { " AND (\($0))" }.joined())
            """,
          arguments: arguments)
        let count = db.changesCount

        let coverage = try Self.searchIndexCoverage(db, serverID: serverID)
        let evaluation = LocalEvaluation(
          evaluatedAt: now,
          documents: coverage.documents,
          documentsWithText: plan.searchesText ? coverage.indexedDocuments : nil,
          limitations: LocalEvaluation.Limitation.allCases.filter(plan.limitations.contains))

        // The basis is the generation as it stands: every mark so far is on a
        // row this order was just computed from.
        let generation =
          try Self.fetchQueryMeta(db, queryKey: queryKey, serverID: serverID)?.orderGeneration ?? 0
        try Self.setQueryMeta(
          db, serverID: serverID, queryKey: queryKey, totalCount: UInt(count),
          basis: QueryOrderGeneration(generation), stamp: .cleared)
        try Self.setLocalEvaluation(db, evaluation, queryKey: queryKey, serverID: serverID)
        return evaluation
      }
    }
  }

  // MARK: - The mark

  static func setLocalEvaluation(
    _ db: GRDB.Database, _ evaluation: LocalEvaluation?, queryKey: QueryKey, serverID: UUID
  ) throws {
    let json = try evaluation.map {
      String(decoding: try ElementStorage.encoder.encode($0), as: UTF8.self)
    }
    try db.cachedStatement(
      sql: """
        UPDATE query_meta SET local_evaluation = ?1
        WHERE server_id = ?2 AND query_key = ?3 AND local_evaluation IS NOT ?1
        """
    ).execute(arguments: [json, serverID, queryKey.rawValue])
  }

  static func fetchLocalEvaluation(
    _ db: GRDB.Database, queryKey: QueryKey, serverID: UUID
  ) throws -> LocalEvaluation? {
    let json = try String.fetchOne(
      db.cachedStatement(
        sql: "SELECT local_evaluation FROM query_meta WHERE server_id = ? AND query_key = ?"),
      arguments: [serverID, queryKey.rawValue])
    guard let json else { return nil }
    // A value this build can't read is treated as no mark: the list then
    // shows as an ordinary incomplete one.
    return try? ElementStorage.decoder.decode(LocalEvaluation.self, from: Data(json.utf8))
  }

  // MARK: - SQL functions

  /// `swp_contains(text, needle)`: whether `text` contains `needle`, ignoring
  /// case and diacritics. `needle` must already be folded with
  /// ``LocalSearchText/fold(_:)``. SQLite's `LIKE` only folds ASCII, which
  /// would make "überweisung" miss "Überweisung".
  static let containsFunction = DatabaseFunction(
    "swp_contains", argumentCount: 2, pure: true
  ) { values in
    guard let text = String.fromDatabaseValue(values[0]),
      let needle = String.fromDatabaseValue(values[1])
    else { return false }
    return LocalSearchText.fold(text).contains(needle)
  }
}

/// How a search text is split up and matched on the device.
enum LocalSearchText {
  /// Case- and diacritic-insensitive form, the same folding the index's
  /// tokenizer (`unicode61 remove_diacritics 2`) applies.
  static func fold(_ text: String) -> String {
    text.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
  }

  /// The words of a search text, folded: what the user separated by spaces.
  static func words(_ text: String) -> [String] {
    fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  /// The words of an advanced query, with its syntax taken off, and whether
  /// anything was dropped on the way.
  ///
  /// The server parses field prefixes (`tag:invoice`, `created:[2020 to 2021]`),
  /// boolean operators and wildcards. None of that is evaluated here: field
  /// terms and operators are dropped, and what is left is searched as words.
  static func advancedWords(_ text: String) -> (words: [String], simplified: Bool) {
    var simplified = false
    var words: [String] = []
    // A bracketed range may hold spaces; it belongs to a field term, whose
    // prefix stays behind and gets the term dropped below.
    var remainder = text
    while let open = remainder.firstIndex(of: "["),
      let close = remainder[open...].firstIndex(of: "]")
    {
      remainder.removeSubrange(open...close)
      simplified = true
    }
    for raw in remainder.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
      if raw.contains(":") || ["AND", "OR", "NOT", "TO"].contains(String(raw)) {
        simplified = true
        continue
      }
      let stripped = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'()*+-~^?[]"))
      if stripped.count != raw.count { simplified = true }
      if !stripped.isEmpty { words.append(fold(stripped)) }
    }
    return (words, simplified)
  }

  /// The index tokens of one word: its runs of letters and digits, which is
  /// how the tokenizer splits text. "2024-07" is the tokens "2024" and "07".
  static func tokens(_ word: String) -> [String] {
    word.unicodeScalars
      .split(whereSeparator: { !CharacterSet.alphanumerics.contains($0) })
      .map { String(String.UnicodeScalarView($0)) }
  }

  /// The full-text query matching every token of `word` as a word prefix, or
  /// `nil` if the word has no tokens. A single character is matched whole:
  /// its prefix would match a large part of the index.
  static func matchExpression(_ word: String) -> String? {
    let tokens = tokens(word)
    guard !tokens.isEmpty else { return nil }
    return
      tokens
      .map { token in
        let quoted = "\"" + token.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        return token.count > 1 ? quoted + "*" : quoted
      }
      .joined(separator: " AND ")
  }
}

/// A filter turned into the `WHERE` conditions and the `ORDER BY` of a query
/// over `document d`.
struct LocalQueryPlan {
  private(set) var conditions: [String] = []
  private(set) var conditionArguments: StatementArguments = []
  private(set) var order = ""
  private(set) var orderArguments: StatementArguments = []
  private(set) var limitations: Set<LocalEvaluation.Limitation> = []
  /// The filter looks into the documents' texts, so the answer depends on
  /// which texts are on the device.
  private(set) var searchesText = false

  private static func json(_ key: String) -> String { "json_extract(d.data, '$.\(key)')" }

  init(
    _ db: GRDB.Database, filter: FilterState, serverID: UUID, now: Date, calendar: Calendar
  ) throws {
    addElement(filter.correspondent, key: "correspondent")
    addElement(filter.documentType, key: "documentType")
    addElement(filter.storagePath, key: "storagePath")
    addElement(filter.owner, key: "owner")
    addTags(filter.tags)
    addASN(filter.asn)
    addDate(filter.date.created, column: Self.json("created"), now: now, calendar: calendar)
    addDate(filter.date.added, column: Self.json("added"), now: now, calendar: calendar)
    addDate(filter.date.modified, column: "d.modified", now: now, calendar: calendar)

    if filter.customField != .any { limitations.insert(.customFields) }
    if filter.duplicates != .any { limitations.insert(.duplicates) }
    if !filter.remaining.isEmpty { limitations.insert(.otherRules) }

    let titleWords = try addSearch(db, filter: filter, serverID: serverID)
    setOrder(filter.resolvedSorting, titleWords: titleWords)
  }

  // MARK: Conditions

  private mutating func add(_ condition: String, _ arguments: StatementArguments = []) {
    conditions.append(condition)
    conditionArguments += arguments
  }

  private static func list(_ ids: [UInt]) -> String {
    ids.map(String.init).joined(separator: ", ")
  }

  private mutating func addElement(_ filter: FilterState.Filter, key: String) {
    let column = Self.json(key)
    switch filter {
    case .any:
      break
    case .notAssigned:
      add("\(column) IS NULL")
    case .anyOf(let ids):
      add("\(column) IN (\(Self.list(ids)))")
    case .noneOf(let ids):
      add("\(column) IS NULL OR \(column) NOT IN (\(Self.list(ids)))")
    }
  }

  private static func hasTag(in ids: [UInt]) -> String {
    "EXISTS (SELECT 1 FROM json_each(d.data, '$.tags') WHERE value IN (\(list(ids))))"
  }

  private mutating func addTags(_ filter: FilterState.TagFilter) {
    switch filter {
    case .any:
      break
    case .notAssigned:
      add("json_array_length(d.data, '$.tags') = 0")
    case .allOf(let include, let exclude):
      for id in include {
        add(Self.hasTag(in: [id]))
      }
      if !exclude.isEmpty {
        add("NOT " + Self.hasTag(in: exclude))
      }
    case .anyOf(let ids):
      add(Self.hasTag(in: ids))
    }
  }

  private mutating func addASN(_ filter: FilterState.AsnFilter) {
    switch filter {
    case .any: break
    case .isNull: add("d.asn IS NULL")
    case .isNotNull: add("d.asn IS NOT NULL")
    case .equalTo(let value): add("d.asn = ?", [value])
    case .lessThan(let value): add("d.asn < ?", [value])
    case .greaterThan(let value): add("d.asn > ?", [value])
    }
  }

  /// `column` holds reference-date seconds, like every stored date.
  private mutating func addDate(
    _ argument: FilterState.DateFilter.Argument, column: String, now: Date, calendar: Calendar
  ) {
    guard let interval = argument.interval(now: now, calendar: calendar) else { return }
    if let start = interval.start {
      add("\(column) >= ?", [start.timeIntervalSinceReferenceDate])
    }
    if let end = interval.end {
      add("\(column) < ?", [end.timeIntervalSinceReferenceDate])
    }
  }

  // MARK: Search

  /// Adds the text search's conditions. Returns the words a title is scored
  /// by under the relevance sort.
  private mutating func addSearch(
    _ db: GRDB.Database, filter: FilterState, serverID: UUID
  ) throws -> [String] {
    guard !filter.searchText.isEmpty else { return [] }

    let title = { (word: String) -> (String, StatementArguments) in
      ("swp_contains(d.title, ?)", [word])
    }
    let content = { (word: String) -> (String, StatementArguments)? in
      guard let match = LocalSearchText.matchExpression(word) else { return nil }
      return (
        """
        d.id IN (
          SELECT ci.document_id FROM content_fts
          JOIN content_index ci ON ci.id = content_fts.rowid
          WHERE content_fts MATCH ? AND ci.server_id = ?)
        """, [match, serverID]
      )
    }
    /// One condition per word; a word matches if any of its alternatives do.
    func require(
      _ words: [String], _ alternatives: (String) -> [(String, StatementArguments)?]
    ) {
      for word in words {
        let matching = alternatives(word).compactMap { $0 }
        guard !matching.isEmpty else {
          // Nothing can match a word made of punctuation alone.
          add("0")
          continue
        }
        add(
          matching.map(\.0).joined(separator: " OR "),
          matching.map(\.1).reduce(into: StatementArguments()) { $0 += $1 })
      }
    }

    switch filter.searchMode {
    case .title:
      let words = LocalSearchText.words(filter.searchText)
      require(words) { [title($0)] }
      return words
    case .content:
      let words = LocalSearchText.words(filter.searchText)
      searchesText = true
      require(words) { [content($0)] }
      return []
    case .titleContent:
      let words = LocalSearchText.words(filter.searchText)
      searchesText = true
      require(words) { [title($0), content($0)] }
      return words
    case .advanced:
      let (words, simplified) = LocalSearchText.advancedWords(filter.searchText)
      if simplified { limitations.insert(.advancedSyntax) }
      guard !words.isEmpty else { return [] }
      searchesText = true
      let names = try ElementNames(db, serverID: serverID)
      require(words) { word in
        var alternatives: [(String, StatementArguments)?] = [
          title(word), content(word),
          ("swp_contains(\(Self.json("originalFileName")), ?)", [word]),
        ]
        if let asn = UInt(word) {
          alternatives.append(("d.asn = ?", [asn]))
        }
        for (key, table) in ElementNames.single {
          let ids = names.ids(in: table, matching: word)
          if !ids.isEmpty {
            alternatives.append(("\(Self.json(key)) IN (\(Self.list(ids)))", []))
          }
        }
        let tags = names.ids(in: "tag", matching: word)
        if !tags.isEmpty {
          alternatives.append((Self.hasTag(in: tags), []))
        }
        return alternatives
      }
      return words
    }
  }

  // MARK: Order

  private mutating func setOrder(_ sorting: FilterState.Sorting, titleWords: [String]) {
    let direction = sorting.order == .ascending ? "ASC" : "DESC"
    /// Sorted by the name of the element a document points at, the documents
    /// without one last.
    func byName(key: String, table: String) -> String {
      let id = Self.json(key)
      return """
        \(id) IS NULL, (SELECT e.name FROM \(table) e
          WHERE e.server_id = d.server_id AND e.id = \(id)) COLLATE NOCASE \(direction)
        """
    }
    let newestFirst = "\(Self.json("created")) DESC"

    let primary: String
    switch sorting.field {
    case .asn: primary = "d.asn IS NULL, d.asn \(direction)"
    case .title: primary = "d.title COLLATE NOCASE \(direction)"
    case .created: primary = "\(Self.json("created")) \(direction)"
    case .added: primary = "\(Self.json("added")) \(direction)"
    case .modified: primary = "d.modified \(direction)"
    case .correspondent: primary = byName(key: "correspondent", table: "correspondent")
    case .documentType: primary = byName(key: "documentType", table: "document_type")
    case .storagePath: primary = byName(key: "storagePath", table: "storage_path")
    case .owner: primary = "\(Self.json("owner")) \(direction)"
    case .notes: primary = "d.notes_count \(direction)"
    case .pageCount: primary = "\(Self.json("pageCount")) \(direction)"
    case .score:
      // The server's relevance isn't reproduced. Documents with more of the
      // words in their title come first, then the newest.
      if titleWords.isEmpty {
        primary = newestFirst
      } else {
        let hits = titleWords.map { _ in "swp_contains(d.title, ?)" }.joined(separator: " + ")
        orderArguments += StatementArguments(titleWords)
        primary = "(\(hits)) DESC, \(newestFirst)"
      }
    case .customField, .other:
      limitations.insert(.sorting)
      primary = newestFirst
    }
    // The id settles ties, so the order is the same on every run.
    order = "\(primary), d.id DESC"
  }
}

/// The names of a server's cached elements, folded, for matching a search
/// word against them.
private struct ElementNames {
  /// Payload key and table of the elements a document points at with one id.
  static let single = [
    ("correspondent", "correspondent"), ("documentType", "document_type"),
    ("storagePath", "storage_path"),
  ]

  private var names: [String: [(id: UInt, name: String)]] = [:]

  init(_ db: GRDB.Database, serverID: UUID) throws {
    for table in Self.single.map(\.1) + ["tag"] {
      names[table] = try Row.fetchAll(
        db, sql: "SELECT id, name FROM \(table) WHERE server_id = ?", arguments: [serverID]
      ).map { (id: $0["id"], name: LocalSearchText.fold($0["name"])) }
    }
  }

  func ids(in table: String, matching word: String) -> [UInt] {
    (names[table] ?? []).filter { $0.name.contains(word) }.map(\.id)
  }
}
