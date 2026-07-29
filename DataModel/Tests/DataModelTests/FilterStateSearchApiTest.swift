//
//  FilterStateSearchApiTest.swift
//  DataModel
//
//  Covers the pre-3.0 (`title_content`) vs 3.0+ (`text`) encodings of the
//  "title and content" search mode.
//

import Foundation
import Testing

@testable import DataModel

/// The two parameter names that carry a "title and content" search.
private let legacySearchParameter = "title_content"
private let tantivySearchParameter = "text"

/// Parameters paperless-ngx 3.0 answers through its search index. It rejects
/// requests carrying more than one of them with HTTP 400.
private let exclusiveSearchParameters: Set<String> = [
  "text", "title_search", "query", "more_like_id",
]

/// Encodes a state the way `Endpoint.documents` does, grouped by parameter name
/// so the comparison does not depend on the (dictionary-derived) rule order.
private func encoded(_ state: FilterState, for searchApi: FilterState.SearchApi) -> [String:
  [String]]
{
  Dictionary(grouping: FilterRule.queryItems(for: state.rules(for: searchApi))) { $0.name }
    .mapValues { $0.compactMap(\.value).sorted() }
}

private func withoutSearchParameters(_ items: [String: [String]]) -> [String: [String]] {
  items.filter { $0.key != legacySearchParameter && !exclusiveSearchParameters.contains($0.key) }
}

private let searchText = "invoice 2024"

/// A value each rule type will accept, so a sweep can instantiate all of them.
/// Custom field queries need a parseable payload and are covered elsewhere.
private func sampleValue(for ruleType: FilterRuleType) -> FilterRuleValue? {
  switch ruleType.dataType() {
  case .boolean: .boolean(value: true)
  case .number: .number(value: 1)
  case .date: .date(value: Date())
  case .tag: .tag(id: 1)
  case .correspondent: .correspondent(id: 1)
  case .documentType: .documentType(id: 1)
  case .storagePath: .storagePath(id: 1)
  case .string: ruleType == .customFieldsQuery ? nil : .string(value: "x")
  }
}

/// A state exercising every non-search rule generator at once, so the
/// equivalence checks below are not just comparing two nearly empty rule sets.
private func fullyPopulated(_ factory: (inout FilterState) -> Void) -> FilterState {
  FilterState.empty.with {
    $0.correspondent = .anyOf(ids: [1, 2])
    $0.documentType = .noneOf(ids: [3])
    $0.storagePath = .anyOf(ids: [4])
    $0.owner = .noneOf(ids: [5])
    $0.tags = .allOf(include: [6, 7], exclude: [8])
    $0.asn = .greaterThan(42)
    $0.customField = CustomFieldQuery(rawValue: #"[11,"exists","true"]"#)!
    $0.date.created = .between(
      start: datetime(year: 2024, month: 1, day: 1),
      end: datetime(year: 2024, month: 12, day: 31))
    factory(&$0)
  }
}

/// States where the two encodings are expected to differ only in the name of
/// the search parameter.
private let divergingStates: [(String, FilterState)] = [
  (
    "bare title-and-content search",
    FilterState.empty.with {
      $0.searchMode = .titleContent
      $0.searchText = searchText
    }
  ),
  (
    "title-and-content search alongside every other filter",
    fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
    }
  ),
]

/// States where both encodings are expected to be byte-identical, either
/// because the mode does not use the deprecated parameter at all, or because
/// the exclusivity fallback kicks in.
private let identicalStates: [(String, FilterState)] = [
  ("empty state", FilterState.empty),
  (
    "title-only search",
    fullyPopulated {
      $0.searchMode = .title
      $0.searchText = searchText
    }
  ),
  (
    "content-only search",
    fullyPopulated {
      $0.searchMode = .content
      $0.searchText = searchText
    }
  ),
  (
    "advanced search",
    fullyPopulated {
      $0.searchMode = .advanced
      $0.searchText = "title:invoice"
    }
  ),
  (
    "title-and-content mode with no search text",
    fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = ""
    }
  ),
  (
    "a more_like_id saved view with no search text typed on top",
    fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = ""
      $0.remaining = [FilterRule(ruleType: .fulltextMorelike, value: .number(value: 17))!]
    }
  ),
  (
    "title-only search with a relative created range",
    fullyPopulated {
      $0.searchMode = .title
      $0.searchText = searchText
      $0.date.created = .range(.previousYear)
    }
  ),
]

/// States where the 3.0 encoding folds the search text into the `query` rule
/// instead of emitting a second, colliding search parameter.
private let promotedStates: [(String, FilterState)] = [
  (
    "relative created range",
    fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.created = .range(.within(num: -3, interval: .month))
    }
  ),
  (
    "relative added range",
    fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.added = .range(.previousQuarter)
    }
  ),
  (
    "relative created and added ranges",
    fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.created = .range(.within(num: -1, interval: .week))
      $0.date.added = .range(.today)
    }
  ),
]

private let allStates = divergingStates + identicalStates + promotedStates

@Suite("Legacy vs Tantivy search parameter encoding")
struct FilterStateSearchApiTest {
  // - MARK: Equivalence

  /// Guards the equivalence checks below against passing vacuously: if
  /// `fullyPopulated` silently stopped producing rules, comparing two empty
  /// parameter sets would still succeed.
  @Test("The shared fixture exercises every non-search rule generator", .bug(id: "642"))
  func fixtureIsNotEmpty() {
    let state = fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
    }

    #expect(
      Set(encoded(state, for: .legacy).keys) == [
        "title_content",
        "correspondent__id__in",
        "document_type__id__none",
        "storage_path__id__in",
        "owner__id__none",
        "tags__id__all",
        "tags__id__none",
        "archive_serial_number__gt",
        "custom_field_query",
        "created__date__gte",
        "created__date__lte",
      ])
  }

  @Test(
    "Everything except the search parameters encodes identically for both backends",
    .bug(id: "642"),
    arguments: allStates)
  func nonSearchParametersAreEquivalent(name: String, state: FilterState) {
    let legacy = withoutSearchParameters(encoded(state, for: .legacy))
    let tantivy = withoutSearchParameters(encoded(state, for: .tantivy))
    #expect(legacy == tantivy, "\(name)")
  }

  @Test(
    "The search text itself survives both encodings unchanged",
    .bug(id: "642"),
    arguments: divergingStates)
  func searchTextIsPreserved(name: String, state: FilterState) {
    let legacy = encoded(state, for: .legacy)
    let tantivy = encoded(state, for: .tantivy)

    #expect(legacy[legacySearchParameter] == [state.searchText], "\(name)")
    #expect(legacy[tantivySearchParameter] == nil, "\(name)")

    #expect(tantivy[tantivySearchParameter] == [state.searchText], "\(name)")
    #expect(tantivy[legacySearchParameter] == nil, "\(name)")
  }

  @Test(
    "Renaming the search parameter is the only difference between the encodings",
    .bug(id: "642"),
    arguments: divergingStates)
  func encodingsDifferOnlyInTheParameterName(name: String, state: FilterState) {
    var renamed = encoded(state, for: .legacy)
    renamed[tantivySearchParameter] = renamed.removeValue(forKey: legacySearchParameter)

    #expect(renamed == encoded(state, for: .tantivy), "\(name)")
  }

  @Test(
    "Modes that do not use `title_content` encode identically on both backends",
    .bug(id: "642"),
    arguments: identicalStates)
  func unaffectedStatesAreUnchanged(name: String, state: FilterState) {
    #expect(encoded(state, for: .legacy) == encoded(state, for: .tantivy), "\(name)")
  }

  // - MARK: Where equivalence stops
  //
  // `text` is answered from the search index and cannot be combined with the
  // other index-backed parameters, so a full one-to-one translation of every
  // filter state is not possible.
  //
  // Where a relative date range would collide, the search text is folded into
  // the `query` string instead — the same thing the web UI does in the "carry
  // it over" branch of filter-editor.component.ts, and the same rules this app
  // produces once the filter has round-tripped through a saved view. Matching
  // then goes through the advanced query parser rather than a substring scan.
  //
  // Where a passed-through rule already holds the one search slot, there is
  // nothing to fold into and the deprecated parameter stays.
  //
  // The remaining, deliberately untested, difference is server-side: on 3.0
  // `text` matches per-token substrings against the search index, whereas
  // `title_content` runs a SQL `icontains` over the live rows. Result sets can
  // therefore differ for the same query; the app cannot assert that here.

  @Test(
    "A relative date range folds the search text into `query`",
    .bug(id: "642"),
    arguments: promotedStates)
  func relativeDateRangePromotesSearchText(name: String, state: FilterState) throws {
    let tantivy = encoded(state, for: .tantivy)
    let legacy = encoded(state, for: .legacy)

    // No separate search parameter survives — the query carries the text.
    #expect(tantivy[legacySearchParameter] == nil, "\(name)")
    #expect(tantivy[tantivySearchParameter] == nil, "\(name)")

    // The legacy encoding is untouched: search parameter plus a query holding
    // only the date terms. Prepending the text to it yields the 3.0 query, so
    // no date term is lost or reordered by the fold.
    let dateTerms = try #require(legacy["query"]?.first)
    #expect(legacy[legacySearchParameter] == [state.searchText], "\(name)")
    #expect(tantivy["query"] == ["\(state.searchText),\(dateTerms)"], "\(name)")
  }

  @Test("The folded query matches what a saved-view round trip produces", .bug(id: "642"))
  func promotionMatchesSavedViewRoundTrip() {
    let state = FilterState.empty.with {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.created = .range(.within(num: -3, interval: .month))
    }

    // Storing this filter as a saved view and reading it back turns it into an
    // advanced search, because the `query` rule populates that mode.
    let roundTripped = FilterState.create(using: \.empty, withRules: state.rules)
    #expect(roundTripped.searchMode == .advanced)

    #expect(encoded(state, for: .tantivy) == encoded(roundTripped, for: .tantivy))
    #expect(encoded(state, for: .tantivy)["query"] == ["\(searchText),created:[-3 month to now]"])
  }

  @Test(
    "A typed search supersedes a more_like_id carried in from a saved view",
    .bug(id: "642"),
    arguments: FilterState.SearchApi.allCases)
  func typedSearchSupersedesMoreLikeId(searchApi: FilterState.SearchApi) {
    let savedView = FilterState.empty.with {
      $0.searchMode = .titleContent
      $0.remaining = [FilterRule(ruleType: .fulltextMorelike, value: .number(value: 17))!]
    }

    // Untouched, the saved view keeps filtering by similarity.
    #expect(encoded(savedView, for: searchApi)["more_like_id"] == ["17"])

    // Typing a search takes over that one control, as it does in the web UI.
    let searched = savedView.with { $0.searchText = searchText }
    let encodedSearch = encoded(searched, for: searchApi)
    #expect(encodedSearch["more_like_id"] == nil)
    #expect(
      encodedSearch[searchApi == .tantivy ? tantivySearchParameter : legacySearchParameter]
        == [searchText])
  }

  @Test(
    "At most one index-backed search parameter is ever emitted",
    .bug(id: "642"),
    arguments: allStates, FilterState.SearchApi.allCases)
  func neverEmitsCollidingSearchParameters(
    state: (String, FilterState), searchApi: FilterState.SearchApi
  ) {
    let names = Set(encoded(state.1, for: searchApi).keys)
    #expect(
      names.intersection(exclusiveSearchParameters).count <= 1,
      "\(state.0) / \(searchApi)")
  }

  // - MARK: Rule types

  @Test("Search modes map onto the rule type matching the backend", .bug(id: "642"))
  func searchModeRuleTypes() {
    #expect(FilterState.SearchMode.titleContent.ruleType(for: .legacy) == .titleContent)
    #expect(FilterState.SearchMode.titleContent.ruleType(for: .tantivy) == .simpleText)

    // Only the title-and-content mode changed in 3.0.
    for mode in [FilterState.SearchMode.title, .content, .advanced] {
      #expect(mode.ruleType(for: .legacy) == mode.ruleType(for: .tantivy))
    }

    // The default stays on the encoding every backend understands.
    for mode in FilterState.SearchMode.allCases {
      #expect(mode.ruleType == mode.ruleType(for: .legacy))
    }
  }

  @Test(
    "The bare `rules` property is the legacy encoding",
    .bug(id: "642"),
    arguments: allStates)
  func bareRulesPropertyIsLegacy(name: String, state: FilterState) {
    #expect(state.rules == state.rules(for: .legacy), "\(name)")
  }

  /// Saved views are stored server-side, so writing rule type 19 to a 3.0
  /// backend would leave a deprecated rule behind for every client that reads
  /// it back. The web UI writes 49 there, and so must we.
  @Test("Saved views written for a 3.0 backend carry rule 49, not 19", .bug(id: "642"))
  func savedViewRulesUseTheBackendsEncoding() {
    let state = FilterState.empty.with {
      $0.searchMode = .titleContent
      $0.searchText = searchText
    }

    #expect(state.rules(for: .tantivy).map(\.ruleType) == [.simpleText])
    #expect(state.rules(for: .legacy).map(\.ruleType) == [.titleContent])

    // Rule 19 read back from an older saved view still round-trips into the
    // same mode, so upgrading the stored rule loses nothing.
    let stored = FilterState.create(
      using: \.empty,
      withRules: [FilterRule(ruleType: .titleContent, value: .string(value: searchText))!])
    #expect(stored.rules(for: .tantivy).map(\.ruleType) == [.simpleText])
  }

  @Test("Both rule types round-trip into the same search mode", .bug(id: "642"))
  func bothRuleTypesRoundTrip() {
    #expect(FilterState.SearchMode(ruleType: .titleContent) == .titleContent)
    #expect(FilterState.SearchMode(ruleType: .simpleText) == .titleContent)
    #expect(FilterState.SearchMode(ruleType: .title) == .title)
    #expect(FilterState.SearchMode(ruleType: .simpleTitle) == .title)
  }

  @Test(
    "A saved view written by the 3.0 web UI populates the title-and-content mode",
    .bug(id: "642"))
  func populatesFromSimpleTextRule() {
    let state = FilterState.create(
      using: \.empty,
      withRules: [FilterRule(ruleType: .simpleText, value: .string(value: searchText))!])

    #expect(state.searchMode == .titleContent)
    #expect(state.searchText == searchText)
    // Not parked in `remaining`, which would have re-sent it verbatim.
    #expect(state.remaining.isEmpty)

    #expect(encoded(state, for: .legacy)[legacySearchParameter] == [searchText])
    #expect(encoded(state, for: .tantivy)[tantivySearchParameter] == [searchText])
  }

  @Test(
    "A saved view written by the 3.0 web UI populates the title-only mode",
    .bug(id: "642"))
  func populatesFromSimpleTitleRule() {
    let state = FilterState.create(
      using: \.empty,
      withRules: [FilterRule(ruleType: .simpleTitle, value: .string(value: searchText))!])

    #expect(state.searchMode == .title)
    #expect(state.searchText == searchText)
    #expect(state.remaining.isEmpty)
  }

  /// On a 3.0 backend the app must never generate the deprecated parameter.
  /// Sweeping every rule type against every search mode keeps that honest: if a
  /// future rule type stops being handled by `populateWith` and lands in
  /// `remaining`, or a new index-backed one appears, this fails rather than
  /// quietly reintroducing requests that log a deprecation warning.
  @Test("`title_content` is never generated for a 3.0 backend", .bug(id: "642"))
  func neverGeneratesLegacyParameterForTantivy() {
    var residual: [String] = []

    for ruleType in FilterRuleType.allCases {
      guard let value = sampleValue(for: ruleType),
        let rule = FilterRule(ruleType: ruleType, value: value)
      else { continue }

      // Go through the saved-view path rather than assigning `remaining`
      // directly: only rules `populateWith` does not understand end up there,
      // and those are the only ones a server can actually hand us.
      let loaded = FilterState.create(using: \.empty, withRules: [rule])

      for mode in FilterState.SearchMode.allCases {
        // The user then types into the search field on top of the saved view.
        let state = loaded.with {
          $0.searchMode = mode
          $0.searchText = searchText
        }
        if encoded(state, for: .tantivy)[legacySearchParameter] != nil {
          residual.append("\(ruleType) + \(mode)")
        }
      }
    }

    #expect(residual == [])
  }

  @Test("Only the index-backed rule types are flagged as exclusive", .bug(id: "642"))
  func exclusiveSearchRuleFlag() {
    let exclusive = FilterRuleType.allCases.filter(\.isExclusiveSearchRule)
    #expect(Set(exclusive) == [.simpleText, .simpleTitle, .fulltextQuery, .fulltextMorelike])
    #expect(Set(exclusive.compactMap { $0.filterVar() }) == exclusiveSearchParameters)
  }
}
