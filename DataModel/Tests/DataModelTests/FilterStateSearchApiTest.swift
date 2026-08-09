//
//  FilterStateSearchApiTest.swift
//  DataModel
//
//  Covers the pre-3.0 (`title_content`, `title__icontains`) vs 3.0+ (`text`,
//  `title_search`) encodings of the text-search modes.
//

import Foundation
import Testing

@testable import DataModel

/// The parameter names carrying a "title and content" search.
private let legacyTitleContentParameter = "title_content"
private let tantivyTitleContentParameter = "text"

/// The parameter names carrying a title-only search.
private let legacyTitleParameter = "title__icontains"
private let tantivyTitleParameter = "title_search"

/// Parameters paperless-ngx 3.0 answers through its search index. It rejects
/// requests carrying more than one of them with HTTP 400.
private let exclusiveSearchParameters: Set<String> = [
  "text", "title_search", "query", "more_like_id",
]

/// The ORM parameters the 3.0 encoding replaces. Neither may appear in a
/// request generated for a 3.0 backend.
///
/// `content__icontains` is deliberately absent: the web UI has no content-only
/// search, so there is no Tantivy parameter to swap it for and it stays put on
/// both backends.
private let supersededSearchParameters: Set<String> = [
  legacyTitleContentParameter, legacyTitleParameter,
]

/// Every parameter that can carry the search text under either encoding.
private let searchTextParameters =
  exclusiveSearchParameters
  .union(supersededSearchParameters)
  .union(["content__icontains"])

/// Encodes a state the way `Endpoint.documents` does, grouped by parameter name
/// so the comparison does not depend on the (dictionary-derived) rule order.
private func encoded(_ state: FilterState, for searchApi: FilterState.SearchApi) -> [String:
  [String]]
{
  Dictionary(grouping: FilterRule.queryItems(for: state.rules(for: searchApi))) { $0.name }
    .mapValues { $0.compactMap(\.value).sorted() }
}

private func withoutSearchParameters(_ items: [String: [String]]) -> [String: [String]] {
  items.filter { !searchTextParameters.contains($0.key) }
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

/// A state whose two encodings differ only in the name of the parameter
/// carrying the search text.
private struct DivergingState: Sendable {
  let name: String
  let state: FilterState
  /// Where the pre-3.0 encoding puts the search text.
  let legacyParameter: String
  /// Where the 3.0 encoding puts it instead.
  let tantivyParameter: String
}

private let divergingStates: [DivergingState] = [
  DivergingState(
    name: "bare title-and-content search",
    state: FilterState.empty.with {
      $0.searchMode = .titleContent
      $0.searchText = searchText
    },
    legacyParameter: legacyTitleContentParameter,
    tantivyParameter: tantivyTitleContentParameter
  ),
  DivergingState(
    name: "title-and-content search alongside every other filter",
    state: fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
    },
    legacyParameter: legacyTitleContentParameter,
    tantivyParameter: tantivyTitleContentParameter
  ),
  DivergingState(
    name: "bare title-only search",
    state: FilterState.empty.with {
      $0.searchMode = .title
      $0.searchText = searchText
    },
    legacyParameter: legacyTitleParameter,
    tantivyParameter: tantivyTitleParameter
  ),
  DivergingState(
    name: "title-only search alongside every other filter",
    state: fullyPopulated {
      $0.searchMode = .title
      $0.searchText = searchText
    },
    legacyParameter: legacyTitleParameter,
    tantivyParameter: tantivyTitleParameter
  ),
]

/// States where both encodings are expected to be byte-identical, either
/// because the mode does not use the deprecated parameter at all, or because
/// the exclusivity fallback kicks in.
private let identicalStates: [(String, FilterState)] = [
  ("empty state", FilterState.empty),
  (
    // The web UI has no content-only search, so nothing is mirrored here.
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
]

/// A state where the 3.0 encoding folds the search text into the `query` rule
/// instead of emitting a second, colliding search parameter.
private struct PromotedState: Sendable {
  let name: String
  let state: FilterState
  /// Where the pre-3.0 encoding still puts the search text. The 3.0 encoding
  /// has no separate parameter at all.
  let legacyParameter: String
}

private let promotedStates: [PromotedState] = [
  PromotedState(
    name: "relative created range",
    state: fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.created = .range(.within(num: -3, interval: .month))
    },
    legacyParameter: legacyTitleContentParameter
  ),
  PromotedState(
    name: "relative added range",
    state: fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.added = .range(.previousQuarter)
    },
    legacyParameter: legacyTitleContentParameter
  ),
  PromotedState(
    name: "relative created and added ranges",
    state: fullyPopulated {
      $0.searchMode = .titleContent
      $0.searchText = searchText
      $0.date.created = .range(.within(num: -1, interval: .week))
      $0.date.added = .range(.today)
    },
    legacyParameter: legacyTitleContentParameter
  ),
  // Title-only search is index-backed on 3.0 too, so it folds identically.
  PromotedState(
    name: "title-only search with a relative created range",
    state: fullyPopulated {
      $0.searchMode = .title
      $0.searchText = searchText
      $0.date.created = .range(.previousYear)
    },
    legacyParameter: legacyTitleParameter
  ),
]

private let allStates =
  divergingStates.map { ($0.name, $0.state) }
  + identicalStates
  + promotedStates.map { ($0.name, $0.state) }

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
  fileprivate func searchTextIsPreserved(fixture: DivergingState) {
    let legacy = encoded(fixture.state, for: .legacy)
    let tantivy = encoded(fixture.state, for: .tantivy)

    #expect(legacy[fixture.legacyParameter] == [fixture.state.searchText], "\(fixture.name)")
    #expect(legacy[fixture.tantivyParameter] == nil, "\(fixture.name)")

    #expect(tantivy[fixture.tantivyParameter] == [fixture.state.searchText], "\(fixture.name)")
    #expect(tantivy[fixture.legacyParameter] == nil, "\(fixture.name)")
  }

  @Test(
    "Renaming the search parameter is the only difference between the encodings",
    .bug(id: "642"),
    arguments: divergingStates)
  fileprivate func encodingsDifferOnlyInTheParameterName(fixture: DivergingState) {
    var renamed = encoded(fixture.state, for: .legacy)
    renamed[fixture.tantivyParameter] = renamed.removeValue(forKey: fixture.legacyParameter)

    #expect(renamed == encoded(fixture.state, for: .tantivy), "\(fixture.name)")
  }

  @Test(
    "Modes with no Tantivy counterpart encode identically on both backends",
    .bug(id: "642"),
    arguments: identicalStates)
  func unaffectedStatesAreUnchanged(name: String, state: FilterState) {
    #expect(encoded(state, for: .legacy) == encoded(state, for: .tantivy), "\(name)")
  }

  // - MARK: Where equivalence stops
  //
  // `text` and `title_search` are answered from the search index and cannot be
  // combined with the other index-backed parameters, so a full one-to-one
  // translation of every filter state is not possible.
  //
  // Where a relative date range would collide, the search text is folded into
  // the `query` string instead — the same thing the web UI does in the "carry
  // it over" branch of filter-editor.component.ts, and the same rules this app
  // produces once the filter has round-tripped through a saved view.
  //
  // Where a passed-through rule already holds the one search slot, there is
  // nothing to fold into and the ORM parameter stays.
  //
  // The remaining, deliberately untested, difference is server-side: on 3.0
  // `text`/`title_search` run a regex against the indexed fields, whereas the
  // ORM filters run a SQL `icontains` over the live rows and the folded `query`
  // is parsed into whole terms. Result sets therefore differ for the same
  // query — a partial word matches under `text` but not once folded — and the
  // app cannot assert any of that here. The web UI has the same behaviour.

  @Test(
    "A relative date range folds the search text into `query`",
    .bug(id: "642"),
    arguments: promotedStates)
  fileprivate func relativeDateRangePromotesSearchText(fixture: PromotedState) throws {
    let tantivy = encoded(fixture.state, for: .tantivy)
    let legacy = encoded(fixture.state, for: .legacy)

    // No separate search parameter survives — the query carries the text.
    #expect(Set(tantivy.keys).intersection(searchTextParameters) == ["query"], "\(fixture.name)")

    // The legacy encoding is untouched: search parameter plus a query holding
    // only the date terms. Prepending the text to it yields the 3.0 query, so
    // no date term is lost or reordered by the fold.
    let dateTerms = try #require(legacy["query"]?.first)
    #expect(legacy[fixture.legacyParameter] == [fixture.state.searchText], "\(fixture.name)")
    #expect(tantivy["query"] == ["\(fixture.state.searchText),\(dateTerms)"], "\(fixture.name)")
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
    let roundTripped = FilterState.create(using: \.empty, withRules: state.rules(for: .legacy))
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
      encodedSearch[
        searchApi == .tantivy ? tantivyTitleContentParameter : legacyTitleContentParameter]
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

    #expect(FilterState.SearchMode.title.ruleType(for: .legacy) == .title)
    #expect(FilterState.SearchMode.title.ruleType(for: .tantivy) == .simpleTitle)

    // The web UI has no content-only search, and advanced search is the `query`
    // parameter on both backends, so neither mode has anything to switch to.
    for mode in [FilterState.SearchMode.content, .advanced] {
      #expect(mode.ruleType(for: .legacy) == mode.ruleType(for: .tantivy))
    }

    // Only the modes routed through the index need the collision handling.
    #expect(FilterState.SearchMode.titleContent.isIndexBacked(for: .tantivy))
    #expect(FilterState.SearchMode.title.isIndexBacked(for: .tantivy))
    #expect(!FilterState.SearchMode.content.isIndexBacked(for: .tantivy))
    #expect(!FilterState.SearchMode.advanced.isIndexBacked(for: .tantivy))
    for mode in FilterState.SearchMode.allCases {
      #expect(!mode.isIndexBacked(for: .legacy))
    }
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

    #expect(encoded(state, for: .legacy)[legacyTitleContentParameter] == [searchText])
    #expect(encoded(state, for: .tantivy)[tantivyTitleContentParameter] == [searchText])
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

    #expect(encoded(state, for: .legacy)[legacyTitleParameter] == [searchText])
    #expect(encoded(state, for: .tantivy)[tantivyTitleParameter] == [searchText])
  }

  /// On a 3.0 backend the app must never generate the superseded parameters.
  /// Sweeping every rule type against every search mode keeps that honest: if a
  /// future rule type stops being handled by `populateWith` and lands in
  /// `remaining`, or a new index-backed one appears, this fails rather than
  /// quietly reintroducing requests that log a deprecation warning or diverge
  /// from the web UI.
  @Test("The superseded parameters are never generated for a 3.0 backend", .bug(id: "642"))
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
        let emitted = Set(encoded(state, for: .tantivy).keys)
          .intersection(supersededSearchParameters)
        if !emitted.isEmpty {
          residual.append("\(ruleType) + \(mode) -> \(emitted.sorted())")
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
