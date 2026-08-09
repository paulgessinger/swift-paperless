//
//  FilterState+RuleGeneration.swift
//  DataModel
//
//  Created by Claude on 02.01.26.
//

import Foundation

extension FilterState {
  /// Which set of document-search query parameters the generated rules target.
  ///
  /// Only the ``FilterState/SearchMode/titleContent`` and
  /// ``FilterState/SearchMode/title`` modes differ between the two; every other
  /// rule this type generates is encoded identically.
  public enum SearchApi: Sendable, Equatable, CaseIterable {
    /// Backends before paperless-ngx 3.0. Searching is done with the ORM
    /// filters `title_content` and `title__icontains`, both SQL `icontains`
    /// over the live rows.
    case legacy

    /// paperless-ngx 3.0+ / API v10. Searching is done with the Tantivy-backed
    /// `text` and `title_search` parameters, which the 3.0 web UI uses in place
    /// of the ORM filters.
    ///
    /// `title_content` is outright deprecated there — it still works, but makes
    /// the backend log "Deprecated document filter parameter 'title_content'
    /// used". `title__icontains` is not deprecated; it is swapped anyway so
    /// that a given search returns the same documents in this app as it does in
    /// the web UI.
    case tantivy
  }

  /// Encodes this state as the rules to send to a backend, or to store in a
  /// saved view on it.
  ///
  /// There is deliberately no backend-agnostic overload: the encoding of the
  /// text-search modes depends on the backend, and defaulting to either one
  /// silently produces the wrong request against the other.
  public func rules(for searchApi: SearchApi) -> [FilterRule] {
    // The web UI treats "more like this" and a text search as two settings of
    // one control: its text field is read-only while more-like is selected,
    // and switching to a text search clears the more-like document
    // (`changeTextFilterTarget` in filter-editor.component.ts). It therefore
    // never emits both. Mirror that — a search the user typed supersedes a
    // `more_like_id` carried in from a saved view built elsewhere.
    var result =
      searchText.isEmpty ? remaining : remaining.filter { $0.ruleType != .fulltextMorelike }

    // paperless-ngx 3.0 answers `text` and `title_search` from its search index
    // and rejects any request carrying more than one index-backed parameter
    // (`text`, `title_search`, `query`, `more_like_id`) with HTTP 400. The ORM
    // filters they replace combine freely, which is why this only matters for
    // the new encoding.
    //
    // No rule reaching `remaining` holds that slot today — `more_like_id` was
    // the only one, and it is gone by now. This is a safety net: should a
    // future rule type stop being understood and land here, degrade to the
    // ORM encoding rather than provoke a 400.
    let passedThroughSearchRule = result.contains { $0.ruleType.isExclusiveSearchRule }
    let usesIndexedSearch =
      searchApi == .tantivy && searchMode.isIndexBacked(for: .tantivy)
      && !passedThroughSearchRule

    // Relative date ranges are expressed as a `query`, which does collide. The
    // web UI resolves this by folding the search text into the query string
    // rather than emitting two parameters — see the "carry it over" branch in
    // filter-editor.component.ts — so mirror that. It is also what this app
    // already produces once such a filter has round-tripped through a saved
    // view, because `query` rules populate the advanced search mode.
    //
    // Note that this changes how the text matches: `text`/`title_search` run a
    // regex over the indexed fields, so a partial word still matches, whereas
    // the folded `query` is parsed into whole terms and no longer does. The web
    // UI has the same behaviour, and matching it is the point.
    let promoteSearchTextIntoQuery = usesIndexedSearch && hasRelativeDateRange

    if !promoteSearchTextIntoQuery {
      result += searchRules(for: usesIndexedSearch ? .tantivy : .legacy)
    }
    result += fulltextQueryRules(promotingSearchText: promoteSearchTextIntoQuery)
    result += correspondentRules
    result += documentTypeRules
    result += storagePathRules
    result += tagRules
    result += ownerRules
    result += customFieldRules
    result += asnRules
    result += dateBetweenRules
    return result
  }

  private func searchRules(for searchApi: SearchApi) -> [FilterRule] {
    guard !searchText.isEmpty else { return [] }
    guard searchMode != .advanced else { return [] }
    return [
      FilterRule(ruleType: searchMode.ruleType(for: searchApi), value: .string(value: searchText))!
    ]
  }

  /// Whether the date filters produce a `query` rule, which is the only
  /// index-backed parameter this type emits outside of advanced search.
  private var hasRelativeDateRange: Bool {
    for argument in [date.created, date.added, date.modified] {
      if case .range = argument { return true }
    }
    return false
  }

  private func fulltextQueryRules(promotingSearchText: Bool) -> [FilterRule] {
    var components: [String] = []

    if searchMode == .advanced || promotingSearchText, !searchText.isEmpty {
      components.append(searchText)
    }

    if case .range(let range) = date.created {
      components.append("created:\(fulltextQueryValue(for: range))")
    }

    if case .range(let range) = date.added {
      components.append("added:\(fulltextQueryValue(for: range))")
    }

    if case .range(let range) = date.modified {
      components.append("modified:\(fulltextQueryValue(for: range))")
    }

    guard !components.isEmpty else { return [] }
    let value = components.joined(separator: ",")
    return [FilterRule(ruleType: .fulltextQuery, value: .string(value: value))!]
  }

  private func fulltextQueryValue(for range: DateFilter.Range) -> String {
    switch range {
    case .within:
      return range.rawValue
    case .currentYear,
      .currentMonth,
      .today,
      .yesterday,
      .previousWeek,
      .previousMonth,
      .previousQuarter,
      .previousYear:
      return "\"\(range.rawValue)\""
    }
  }

  private var correspondentRules: [FilterRule] {
    var result: [FilterRule] = []
    switch correspondent {
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: id))!
        )
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: id))!
        )
      }
    case .any: break
    }
    return result
  }

  private var documentTypeRules: [FilterRule] {
    var result: [FilterRule] = []
    switch documentType {
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .documentType, value: .documentType(id: nil))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: id))!
        )
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: id))!
        )
      }
    case .any: break
    }
    return result
  }

  private var storagePathRules: [FilterRule] {
    var result: [FilterRule] = []
    switch storagePath {
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .storagePath, value: .storagePath(id: nil))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: id))!
        )
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: id))!
        )
      }
    case .any: break
    }
    return result
  }

  private var tagRules: [FilterRule] {
    var result: [FilterRule] = []
    switch tags {
    case .any: break
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false))!
      )
    case .allOf(let include, let exclude):
      for id in include {
        result.append(
          FilterRule(ruleType: .hasTagsAll, value: .tag(id: id))!
        )
      }
      for id in exclude {
        result.append(
          FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: id))!
        )
      }
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasTagsAny, value: .tag(id: id))!
        )
      }
    }
    return result
  }

  private var ownerRules: [FilterRule] {
    var result: [FilterRule] = []
    switch owner {
    case .any: break
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(FilterRule(ruleType: .ownerAny, value: .number(value: Int(id)))!)
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: Int(id)))!)
      }
    }
    return result
  }

  private var customFieldRules: [FilterRule] {
    guard customField != .any else { return [] }
    return [FilterRule(ruleType: .customFieldsQuery, value: .customFieldQuery(customField))!]
  }

  private var asnRules: [FilterRule] {
    var result: [FilterRule] = []
    switch asn {
    case .any: break
    case .isNull:
      result.append(
        FilterRule(ruleType: .asnIsnull, value: .boolean(value: true))!
      )
    case .isNotNull:
      result.append(
        FilterRule(ruleType: .asnIsnull, value: .boolean(value: false))!
      )
    case .equalTo(let value):
      result.append(
        FilterRule(ruleType: .asn, value: .number(value: Int(value)))!
      )
    case .greaterThan(let value):
      result.append(
        FilterRule(ruleType: .asnGt, value: .number(value: Int(value)))!
      )
    case .lessThan(let value):
      result.append(
        FilterRule(ruleType: .asnLt, value: .number(value: Int(value)))!
      )
    }
    return result
  }

  private var dateBetweenRules: [FilterRule] {
    var result: [FilterRule] = []

    if case .between(let start, let end) = date.created {
      if let start {
        result.append(FilterRule(ruleType: .createdFrom, value: .date(value: start))!)
      }
      if let end {
        result.append(FilterRule(ruleType: .createdTo, value: .date(value: end))!)
      }
    }

    if case .between(let start, let end) = date.added {
      if let start {
        result.append(FilterRule(ruleType: .addedFrom, value: .date(value: start))!)
      }
      if let end {
        result.append(FilterRule(ruleType: .addedTo, value: .date(value: end))!)
      }
    }

    if case .between(let start, let end) = date.modified {
      // WORKAROUND: modifiedAfter/Before use exclusive (gt/lt) semantics, but FilterState uses
      // inclusive bounds. We need to adjust the dates when generating rules:
      // - For start (inclusive), we subtract 1 day to get "modified > start-1" (exclusive)
      // - For end (inclusive), we add 1 day to get "modified < end+1" (exclusive)
      // If the backend adds modifiedFrom/To (gte/lte) in the future, we should switch to those.
      if let start {
        let adjustedStart = Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start
        result.append(FilterRule(ruleType: .modifiedAfter, value: .date(value: adjustedStart))!)
      }
      if let end {
        let adjustedEnd = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        result.append(FilterRule(ruleType: .modifiedBefore, value: .date(value: adjustedEnd))!)
      }
    }

    return result
  }
}
