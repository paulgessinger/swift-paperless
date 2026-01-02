//
//  FilterStateTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 02.04.23.
//

import Foundation
import Testing

@testable import DataModel

private func datetime(year: Int, month: Int, day: Int) -> Date {
  var dateComponents = DateComponents()
  dateComponents.year = year
  dateComponents.month = month
  dateComponents.day = day
  dateComponents.timeZone = TimeZone(abbreviation: "UTC")
  dateComponents.hour = 0
  dateComponents.minute = 0

  let date = Calendar.current.date(from: dateComponents)!
  return date
}

private func stringValue(from rule: FilterRule) -> String? {
  guard case .string(let value) = rule.value else {
    return nil
  }
  return value
}

private func queryComponents(from value: String) -> Set<String> {
  Set(
    value
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
  )
}

extension FilterState {
  fileprivate init(rules: [FilterRule]) {
    self = .create(using: \.empty, withRules: rules)
  }
}

@Suite
struct FilterStateTest {
  // - MARK: FilterRule to FilterState

  @Test("Search mode conversion between FilterRuleType and FilterState.SearchMode")
  func testSearchModeConversion() {
    #expect(FilterRuleType.title == FilterState.SearchMode.title.ruleType)
    #expect(FilterRuleType.content == FilterState.SearchMode.content.ruleType)
    #expect(FilterRuleType.titleContent == FilterState.SearchMode.titleContent.ruleType)

    #expect(FilterState.SearchMode(ruleType: .title) == FilterState.SearchMode.title)
    #expect(FilterState.SearchMode(ruleType: .content) == FilterState.SearchMode.content)
    #expect(FilterState.SearchMode(ruleType: .titleContent) == FilterState.SearchMode.titleContent)
  }

  @Test("Convert text search rules to FilterState")
  func testRuleToFilterStateTextSearch() throws {
    for mode in [FilterRuleType](
      [.title, .content, .titleContent])
    {
      let state = try FilterState(rules: [
        #require(FilterRule(ruleType: mode, value: .string(value: "hallo")))
      ])
      #expect(
        state
          == FilterState.empty.with {
            $0.searchText = "hallo"
            $0.searchMode = .init(ruleType: mode)!
          }
      )
      #expect(state.remaining.isEmpty)
    }
  }

  @Test("Convert correspondent rules to FilterState")
  func testRuleToFilterStateCorrespondent() throws {
    // Old single rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .correspondent, value: .correspondent(id: 8)))
      ]) == FilterState.empty.with { $0.correspondent = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .correspondent, value: .correspondent(id: nil)))
      ]) == FilterState.empty.with { $0.correspondent = .notAssigned }
    )

    // New anyOf rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)))
      ]) == FilterState.empty.with { $0.correspondent = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8))),
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19))),
      ]) == FilterState.empty.with { $0.correspondent = .anyOf(ids: [8, 19]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .invalid(value: "11,12")))
      ]).correspondent == .anyOf(ids: [11, 12]))

    // New noneOf rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)))
      ]) == FilterState.empty.with { $0.correspondent = .noneOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 19))),
      ]) == FilterState.empty.with { $0.correspondent = .noneOf(ids: [8, 19]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .invalid(value: "11,12")))
      ]).correspondent == .noneOf(ids: [11, 12]))

    // @TODO: Test error states
  }

  @Test("Convert document type rules to FilterState")
  func testRuleToFilterStateDocumentType() throws {
    // Old single rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .documentType, value: .documentType(id: 8)))
      ]) == FilterState.empty.with { $0.documentType = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .documentType, value: .documentType(id: nil)))
      ]) == FilterState.empty.with { $0.documentType = .notAssigned }
    )

    // New anyOf rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)))
      ]) == FilterState.empty.with { $0.documentType = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8))),
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19))),
      ]) == FilterState.empty.with { $0.documentType = .anyOf(ids: [8, 19]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .invalid(value: "11,12")))
      ]).documentType == .anyOf(ids: [11, 12]))

    // New noneOf rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)))
      ]) == FilterState.empty.with { $0.documentType = .noneOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 19))),
      ]) == FilterState.empty.with { $0.documentType = .noneOf(ids: [8, 19]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .invalid(value: "11,12")))
      ]).documentType == .noneOf(ids: [11, 12]))

    // @TODO: Test error states
  }

  @Test("Unsupported rules go to remaining array")
  func testRuleToFilterStateRemaining() throws {
    // Unsupported rules go to "remaining":
    let addedAfter = try #require(
      FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
    )
    #expect(
      FilterState(rules: [addedAfter]).remaining == [addedAfter]
    )
  }

  @Test("Convert date between rules to FilterState")
  func testRuleToFilterStateDateBetween() throws {
    let createdStart = datetime(year: 2026, month: 1, day: 1)
    let createdEnd = datetime(year: 2026, month: 1, day: 2)
    let addedStart = datetime(year: 2025, month: 12, day: 31)
    let addedEnd = datetime(year: 2026, month: 1, day: 3)

    let rules = try [FilterRule]([
      #require(FilterRule(ruleType: .createdFrom, value: .date(value: createdStart))),
      #require(FilterRule(ruleType: .createdTo, value: .date(value: createdEnd))),
      #require(FilterRule(ruleType: .addedFrom, value: .date(value: addedStart))),
      #require(FilterRule(ruleType: .addedTo, value: .date(value: addedEnd))),
    ])

    let state = FilterState(rules: rules)
    #expect(state.dateFilter.created == .between(start: createdStart, end: createdEnd))
    #expect(state.dateFilter.added == .between(start: addedStart, end: addedEnd))
    #expect(state.remaining.isEmpty)

    let createdOnlyState = FilterState(rules: [rules[0]])
    #expect(createdOnlyState.dateFilter.created == .between(start: createdStart, end: nil))
    #expect(createdOnlyState.dateFilter.added == .any)

    let addedOnlyState = FilterState(rules: [rules[3]])
    #expect(addedOnlyState.dateFilter.created == .any)
    #expect(addedOnlyState.dateFilter.added == .between(start: nil, end: addedEnd))
  }

  @Test("Parse date ranges from fulltext query rules")
  func testRuleToFilterStateDateWithinFulltextQuery() throws {
    let rules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "created:[-1 week to now],added:[-2 month to now]"))),
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "SEARCH_TERM"))),
    ])

    let state = FilterState(rules: rules)
    #expect(state.searchMode == .advanced)
    #expect(state.searchText == "SEARCH_TERM")
    #expect(state.dateFilter.created == .range(.within(num: -1, interval: .week)))
    #expect(state.dateFilter.added == .range(.within(num: -2, interval: .month)))
    #expect(state.remaining.isEmpty)

    let combinedRules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "SEARCH_TERM,created:[-1 week to now],added:[-2 month to now]")))
    ])

    let combinedState = FilterState(rules: combinedRules)
    #expect(combinedState.searchMode == .advanced)
    #expect(combinedState.searchText == "SEARCH_TERM")
    #expect(combinedState.dateFilter.created == .range(.within(num: -1, interval: .week)))
    #expect(combinedState.dateFilter.added == .range(.within(num: -2, interval: .month)))
    #expect(combinedState.remaining.isEmpty)

    let nonRangeRules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "created:report")))
    ])

    let nonRangeState = FilterState(rules: nonRangeRules)
    #expect(nonRangeState.searchMode == .advanced)
    #expect(nonRangeState.searchText == "created:report")
    #expect(nonRangeState.dateFilter.created == .any)
    #expect(nonRangeState.dateFilter.added == .any)

    let mixedRules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "created:report,created:[-1 week to now]")))
    ])

    let mixedState = FilterState(rules: mixedRules)
    #expect(mixedState.searchMode == .advanced)
    #expect(mixedState.searchText == "created:report")
    #expect(mixedState.dateFilter.created == .range(.within(num: -1, interval: .week)))
    #expect(mixedState.dateFilter.added == .any)

    let keywordRules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "created:\"yesterday\",added:\"previous week\"")))
    ])

    let keywordState = FilterState(rules: keywordRules)
    #expect(keywordState.searchMode == .advanced)
    #expect(keywordState.searchText.isEmpty)
    #expect(keywordState.dateFilter.created == .range(.yesterday))
    #expect(keywordState.dateFilter.added == .range(.previousWeek))

    let unsupportedKeywordRules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "created:\"UNSUPPORTED\"")))
    ])

    let unsupportedKeywordState = FilterState(rules: unsupportedKeywordRules)
    #expect(unsupportedKeywordState.searchMode == .advanced)
    #expect(unsupportedKeywordState.searchText == "created:\"UNSUPPORTED\"")
    #expect(unsupportedKeywordState.dateFilter.created == .any)
    #expect(unsupportedKeywordState.dateFilter.added == .any)

    // The backend won't actually return this form, but let's test it anyway
    let splitRules = try [FilterRule]([
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "created:[-3 month to now]"))),
      #require(
        FilterRule(
          ruleType: .fulltextQuery,
          value: .string(value: "added:[-1 week to now]"))),
    ])

    let splitState = FilterState(rules: splitRules)
    #expect(splitState.searchMode == .advanced)
    #expect(splitState.searchText.isEmpty)
    #expect(splitState.dateFilter.created == .range(.within(num: -3, interval: .month)))
    #expect(splitState.dateFilter.added == .range(.within(num: -1, interval: .week)))
  }

  @Test("Convert tag rules to FilterState")
  func testRuleToFilterStateTags() throws {
    let tagAll = try [FilterRule]([
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 66))),
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 71))),
      #require(FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: 75))),
    ])

    // Single tag all rule
    #expect(
      FilterState(rules: Array(tagAll.prefix(1)))
        == FilterState.empty.with { $0.tags = .allOf(include: [66], exclude: []) }
    )

    #expect(
      FilterState(rules: Array(tagAll.prefix(2)))
        == FilterState.empty.with { $0.tags = .allOf(include: [66, 71], exclude: []) }
    )

    #expect(
      FilterState(rules: tagAll)
        == FilterState.empty.with { $0.tags = .allOf(include: [66, 71], exclude: [75]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasTagsAll, value: .invalid(value: "11,12")))
      ]).tags == .allOf(include: [11, 12], exclude: []))

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveTag, value: .invalid(value: "11,12")))
      ]).tags == .allOf(include: [], exclude: [11, 12]))

    #expect(
      FilterState(rules: Array(tagAll.suffix(1)))
        == FilterState.empty.with { $0.tags = .allOf(include: [], exclude: [75]) }
    )

    #expect(
      FilterState(rules: Array(tagAll.reversed()))
        == FilterState.empty.with { $0.tags = .allOf(include: [71, 66], exclude: [75]) }
    )

    let tagAny = try [FilterRule]([
      #require(FilterRule(ruleType: .hasTagsAny, value: .tag(id: 66))),
      #require(FilterRule(ruleType: .hasTagsAny, value: .tag(id: 71))),
    ])

    #expect(
      FilterState(rules: Array(tagAny.prefix(1)))
        == FilterState.empty.with { $0.tags = .anyOf(ids: [66]) }
    )

    #expect(
      FilterState(rules: tagAny) == FilterState.empty.with { $0.tags = .anyOf(ids: [66, 71]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasTagsAny, value: .invalid(value: "11,12")))
      ]).tags == .anyOf(ids: [11, 12]))

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false)))
      ]) == FilterState.empty.with { $0.tags = .notAssigned }
    )

    // @TODO: Test error states
  }

  @Test("Convert owner rules to FilterState")
  func testRuleToFilterStateOwner() throws {
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .owner, value: .number(value: 8)))
      ]) == FilterState.empty.with { $0.owner = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true)))
      ]) == FilterState.empty.with { $0.owner = .notAssigned }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerIsnull, value: .boolean(value: false)))  // this is pretty odd
      ]) == FilterState.empty.with { $0.owner = .any }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerAny, value: .number(value: 8)))
      ]) == FilterState.empty.with { $0.owner = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerAny, value: .number(value: 8))),
        #require(FilterRule(ruleType: .ownerAny, value: .number(value: 99))),
      ]) == FilterState.empty.with { $0.owner = .anyOf(ids: [8, 99]) }
    )

    // Invalid multi-value recovery
    let rule = try #require(FilterRule(ruleType: .ownerAny, value: .invalid(value: "11,12")))
    #expect(FilterState(rules: [rule]).owner == .anyOf(ids: [11, 12]))

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8)))
      ]) == FilterState.empty.with { $0.owner = .noneOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8))),
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 99))),
      ]) == FilterState.empty.with { $0.owner = .noneOf(ids: [8, 99]) }
    )

    // Invalid multi-value recovery
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .invalid(value: "11,12")))
      ]).owner == .noneOf(ids: [11, 12]))

    // @TODO: Test error states
  }

  @Test("Convert storage path rules to FilterState")
  func testRuleToFilterStateStoragePath() throws {
    // Old single rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .storagePath, value: .storagePath(id: 8)))
      ]) == FilterState.empty.with { $0.storagePath = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .storagePath, value: .storagePath(id: nil)))
      ]) == FilterState.empty.with { $0.storagePath = .notAssigned }
    )

    // New anyOf rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)))
      ]) == FilterState.empty.with { $0.storagePath = .anyOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8))),
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 19))),
      ]) == FilterState.empty.with { $0.storagePath = .anyOf(ids: [8, 19]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .invalid(value: "11,12")))
      ]).storagePath == .anyOf(ids: [11, 12]))

    // New noneOf rule
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)))
      ]) == FilterState.empty.with { $0.storagePath = .noneOf(ids: [8]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 19))),
      ]) == FilterState.empty.with { $0.storagePath = .noneOf(ids: [8, 19]) }
    )

    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .invalid(value: "11,12")))
      ]).storagePath == .noneOf(ids: [11, 12]))

    // @TODO: Test error states
  }

  // - MARK: FilterState to FilterRule

  @Test("Convert FilterState text search to rules")
  func testFilterStateToRuleTextSearch() throws {
    let modes: [FilterState.SearchMode] = [.title, .content, .titleContent]

    for mode in modes {
      let state = FilterState.empty.with {
        $0.searchText = "hallo"
        $0.searchMode = mode
      }

      #expect(
        try state.rules == [
          #require(FilterRule(ruleType: mode.ruleType, value: .string(value: "hallo")))
        ])
    }
  }

  @Test("Convert FilterState date between to rules")
  func testFilterStateToRuleDateBetween() throws {
    let createdStart = datetime(year: 2026, month: 1, day: 1)
    let createdEnd = datetime(year: 2026, month: 1, day: 2)
    let addedStart = datetime(year: 2025, month: 12, day: 31)
    let addedEnd = datetime(year: 2026, month: 1, day: 3)

    let state = FilterState.empty.with {
      $0.dateFilter.created = .between(start: createdStart, end: createdEnd)
      $0.dateFilter.added = .between(start: addedStart, end: addedEnd)
    }

    let expected = try [FilterRule]([
      #require(FilterRule(ruleType: .createdFrom, value: .date(value: createdStart))),
      #require(FilterRule(ruleType: .createdTo, value: .date(value: createdEnd))),
      #require(FilterRule(ruleType: .addedFrom, value: .date(value: addedStart))),
      #require(FilterRule(ruleType: .addedTo, value: .date(value: addedEnd))),
    ])

    let sortedRules = state.rules.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    let sortedExpected = expected.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    #expect(sortedRules == sortedExpected)

    let openEndedState = FilterState.empty.with {
      $0.dateFilter.created = .between(start: createdStart, end: nil)
      $0.dateFilter.added = .between(start: nil, end: addedEnd)
    }

    let openEndedExpected = try [FilterRule]([
      #require(FilterRule(ruleType: .createdFrom, value: .date(value: createdStart))),
      #require(FilterRule(ruleType: .addedTo, value: .date(value: addedEnd))),
    ])

    let sortedOpenEndedRules = openEndedState.rules.sorted(
      by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    let sortedOpenEndedExpected = openEndedExpected.sorted(
      by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    #expect(sortedOpenEndedRules == sortedOpenEndedExpected)
  }

  @Test("Convert FilterState date ranges to fulltext query rules")
  func testFilterStateToRuleDateWithinFulltextQuery() throws {
    let state = FilterState.empty.with {
      $0.searchMode = .advanced
      $0.searchText = "SEARCH_TERM"
      $0.dateFilter.created = .range(.within(num: -1, interval: .week))
      $0.dateFilter.added = .range(.within(num: -2, interval: .month))
    }

    let components = state.rules
      .filter { $0.ruleType == .fulltextQuery }
      .compactMap { stringValue(from: $0) }
      .flatMap { queryComponents(from: $0) }

    #expect(
      Set(components) == [
        "SEARCH_TERM",
        "created:[-1 week to now]",
        "added:[-2 month to now]",
      ])

    let noSearchState = FilterState.empty.with {
      $0.searchMode = .advanced
      $0.searchText = ""
      $0.dateFilter.created = .range(.within(num: -3, interval: .month))
    }

    let noSearchComponents = noSearchState.rules
      .filter { $0.ruleType == .fulltextQuery }
      .compactMap { stringValue(from: $0) }
      .flatMap { queryComponents(from: $0) }

    #expect(
      Set(noSearchComponents) == [
        "created:[-3 month to now]"
      ])
  }

  @Test("Empty FilterState produces no rules")
  func testFilterStateToRuleEmpty() {
    #expect(FilterState.empty.rules == [])
  }

  @Test("Convert FilterState correspondent to rules")
  func testFilterStateToRuleCorrespondent() {
    // Old single rule
    #expect(
      [FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))]
        == FilterState.empty.with { $0.correspondent = .notAssigned }.rules
    )

    // New anyOf rule
    #expect(
      [FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8))]
        == FilterState.empty.with { $0.correspondent = .anyOf(ids: [8]) }.rules
    )

    #expect(
      [
        FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
        FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 99)),
      ] == FilterState.empty.with { $0.correspondent = .anyOf(ids: [8, 99]) }.rules
    )

    // New noneOf rule
    #expect(
      [FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8))]
        == FilterState.empty.with { $0.correspondent = .noneOf(ids: [8]) }.rules
    )

    #expect(
      [
        FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
        FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 99)),
      ] == FilterState.empty.with { $0.correspondent = .noneOf(ids: [8, 99]) }.rules
    )
  }

  @Test("Convert FilterState document type to rules")
  func testFilterStateToRuleDocumentType() {
    // Old single rule
    #expect(
      [FilterRule(ruleType: .documentType, value: .documentType(id: nil))]
        == FilterState.empty.with { $0.documentType = .notAssigned }.rules
    )

    // New anyOf rule
    #expect(
      [FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8))]
        == FilterState.empty.with { $0.documentType = .anyOf(ids: [8]) }.rules
    )

    #expect(
      [
        FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
        FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 99)),
      ] == FilterState.empty.with { $0.documentType = .anyOf(ids: [8, 99]) }.rules)

    // New noneOf rule
    #expect(
      [
        FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8))
      ] == FilterState.empty.with { $0.documentType = .noneOf(ids: [8]) }.rules)

    #expect(
      [
        FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
        FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 99)),
      ] == FilterState.empty.with { $0.documentType = .noneOf(ids: [8, 99]) }.rules)
  }

  @Test("Remaining rules are preserved in round-trip conversion")
  func testFilterStatetoRuleRemaining() throws {
    // Unsupported rules go to "remaining" and are preserved
    let addedAfter = try #require(
      FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
    )
    #expect(
      FilterState(rules: [addedAfter]).rules == [addedAfter]
    )
  }

  @Test("Convert FilterState tags to rules")
  func testFilterStateToRuleTags() throws {
    let tagAll = try [FilterRule]([
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 66))),
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 71))),
      #require(FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: 75))),
    ])

    #expect(
      tagAll == FilterState.empty.with { $0.tags = .allOf(include: [66, 71], exclude: [75]) }.rules
    )

    let tagAny = try [FilterRule]([
      #require(FilterRule(ruleType: .hasTagsAny, value: .tag(id: 66))),
      #require(FilterRule(ruleType: .hasTagsAny, value: .tag(id: 71))),
    ])

    #expect(
      tagAny == FilterState.empty.with { $0.tags = .anyOf(ids: [66, 71]) }.rules
    )

    #expect(
      [FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false))]
        == FilterState.empty.with { $0.tags = .notAssigned }.rules
    )
  }

  @Test("Convert FilterState owner to rules")
  func testFilterStateToRuleOwner() throws {
    #expect(
      [
        FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true))
      ] == FilterState.empty.with { $0.owner = .notAssigned }.rules)

    // This could theoretically be expressed as:
    // FilterRule(ruleType: .ownerIsnull, value: .boolean(value: false))
    // But this is redundant to just not having a rule, so let's not create one.
    #expect(FilterState.empty.with { $0.owner = .any }.rules == [])  // we could the

    #expect(
      try [
        #require(FilterRule(ruleType: .ownerAny, value: .number(value: 8)))
      ] == FilterState.empty.with { $0.owner = .anyOf(ids: [8]) }.rules)

    // Technically, this could also be expressed as a rule .owner with value 8,
    // but that's equivalent

    #expect(
      try [
        #require(FilterRule(ruleType: .ownerAny, value: .number(value: 8))),
        #require(FilterRule(ruleType: .ownerAny, value: .number(value: 99))),
      ] == FilterState.empty.with { $0.owner = .anyOf(ids: [8, 99]) }.rules)

    #expect(
      try [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8)))
      ] == FilterState.empty.with { $0.owner = .noneOf(ids: [8]) }.rules)

    #expect(
      try [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8))),
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 99))),
      ] == FilterState.empty.with { $0.owner = .noneOf(ids: [8, 99]) }.rules)
  }

  @Test("Convert FilterState storage path to rules")
  func testFilterStateToRuleStoragePath() throws {
    // Old single rule
    #expect(
      try [#require(FilterRule(ruleType: .storagePath, value: .storagePath(id: nil)))]
        == FilterState.empty.with { $0.storagePath = .notAssigned }.rules
    )

    // New anyOf rule
    #expect(
      try [#require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)))]
        == FilterState.empty.with { $0.storagePath = .anyOf(ids: [8]) }.rules
    )

    #expect(
      try [
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8))),
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 99))),
      ] == FilterState.empty.with { $0.storagePath = .anyOf(ids: [8, 99]) }.rules)

    // New noneOf rule
    #expect(
      try [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)))
      ] == FilterState.empty.with { $0.storagePath = .noneOf(ids: [8]) }.rules)

    #expect(
      try [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 99))),
      ] == FilterState.empty.with { $0.storagePath = .noneOf(ids: [8, 99]) }.rules)
  }

  // - MARK: ASN Filtering Tests

  @Test("Convert ASN rules to FilterState")
  func testRuleToFilterStateAsn() throws {
    // Test .asn rule with specific value (equalTo)
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .asn, value: .number(value: 42)))
      ]) == FilterState.empty.with { $0.asn = .equalTo(42) }
    )

    // Test .asnIsnull rule with true (isNull)
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .asnIsnull, value: .boolean(value: true)))
      ]) == FilterState.empty.with { $0.asn = .isNull }
    )

    // Test .asnIsnull rule with false (isNotNull)
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .asnIsnull, value: .boolean(value: false)))
      ]) == FilterState.empty.with { $0.asn = .isNotNull }
    )

    // Test .asnGt rule (greaterThan)
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .asnGt, value: .number(value: 100)))
      ]) == FilterState.empty.with { $0.asn = .greaterThan(100) }
    )

    // Test .asnLt rule (lessThan)
    #expect(
      try FilterState(rules: [
        #require(FilterRule(ruleType: .asnLt, value: .number(value: 50)))
      ]) == FilterState.empty.with { $0.asn = .lessThan(50) }
    )
  }

  @Test("Convert FilterState ASN to rules")
  func testFilterStateToRuleAsn() throws {
    // Test .any - should produce no rules
    #expect(
      FilterState.empty.with { $0.asn = .any }.rules == []
    )

    // Test .isNull
    #expect(
      [FilterRule(ruleType: .asnIsnull, value: .boolean(value: true))]
        == FilterState.empty.with { $0.asn = .isNull }.rules
    )

    // Test .isNotNull
    #expect(
      [FilterRule(ruleType: .asnIsnull, value: .boolean(value: false))]
        == FilterState.empty.with { $0.asn = .isNotNull }.rules
    )

    // Test .equalTo
    #expect(
      try [#require(FilterRule(ruleType: .asn, value: .number(value: 42)))]
        == FilterState.empty.with { $0.asn = .equalTo(42) }.rules
    )

    // Test .greaterThan
    #expect(
      try [#require(FilterRule(ruleType: .asnGt, value: .number(value: 100)))]
        == FilterState.empty.with { $0.asn = .greaterThan(100) }.rules
    )

    // Test .lessThan
    #expect(
      try [#require(FilterRule(ruleType: .asnLt, value: .number(value: 50)))]
        == FilterState.empty.with { $0.asn = .lessThan(50) }.rules
    )
  }

  @Test("ASN filter round-trip conversion")
  func testAsnFilterRoundTrip() throws {
    // Test that converting FilterState -> Rules -> FilterState preserves ASN filter state

    // equalTo case
    let equalToState = FilterState.empty.with { $0.asn = .equalTo(42) }
    let equalToRules = equalToState.rules
    #expect(FilterState(rules: equalToRules).asn == .equalTo(42))

    // isNull case
    let isNullState = FilterState.empty.with { $0.asn = .isNull }
    let isNullRules = isNullState.rules
    #expect(FilterState(rules: isNullRules).asn == .isNull)

    // isNotNull case
    let isNotNullState = FilterState.empty.with { $0.asn = .isNotNull }
    let isNotNullRules = isNotNullState.rules
    #expect(FilterState(rules: isNotNullRules).asn == .isNotNull)

    // greaterThan case
    let greaterThanState = FilterState.empty.with { $0.asn = .greaterThan(100) }
    let greaterThanRules = greaterThanState.rules
    #expect(FilterState(rules: greaterThanRules).asn == .greaterThan(100))

    // lessThan case
    let lessThanState = FilterState.empty.with { $0.asn = .lessThan(50) }
    let lessThanRules = lessThanState.rules
    #expect(FilterState(rules: lessThanRules).asn == .lessThan(50))

    // any case (default, produces no rules)
    let anyState = FilterState.empty.with { $0.asn = .any }
    let anyRules = anyState.rules
    #expect(FilterState(rules: anyRules).asn == .any)
  }

  @Test("ASN filter with other filters")
  func testAsnFilterWithOtherFilters() throws {
    // Test ASN filter combined with other filter types
    let rules = try [
      #require(FilterRule(ruleType: .asn, value: .number(value: 42))),
      #require(FilterRule(ruleType: .title, value: .string(value: "test"))),
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 5))),
    ]

    let state = FilterState(rules: rules)
    #expect(state.asn == .equalTo(42))
    #expect(state.searchText == "test")
    #expect(state.searchMode == .title)
    #expect(state.tags == .allOf(include: [5], exclude: []))

    // Verify round-trip preserves all filters
    let regeneratedRules = state.rules.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    let originalRules = rules.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    #expect(regeneratedRules == originalRules)
  }

  @Test("Invalid ASN rule values go to remaining")
  func testInvalidAsnRules() throws {
    // Test that invalid ASN rules are preserved in remaining array

    // Invalid value type for .asn
    let invalidAsnRule = try #require(
      FilterRule(ruleType: .asn, value: .invalid(value: "not-a-number"))
    )
    let state1 = FilterState(rules: [invalidAsnRule])
    #expect(state1.asn == .any)  // Should remain as default
    #expect(state1.remaining.contains(invalidAsnRule))

    // Invalid value type for .asnIsnull
    let invalidAsnNullRule = try #require(
      FilterRule(ruleType: .asnIsnull, value: .invalid(value: "invalid"))
    )
    let state2 = FilterState(rules: [invalidAsnNullRule])
    #expect(state2.asn == .any)
    #expect(state2.remaining.contains(invalidAsnNullRule))

    // Invalid value type for .asnGt
    let invalidAsnGtRule = try #require(
      FilterRule(ruleType: .asnGt, value: .invalid(value: "invalid"))
    )
    let state3 = FilterState(rules: [invalidAsnGtRule])
    #expect(state3.asn == .any)
    #expect(state3.remaining.contains(invalidAsnGtRule))

    // Invalid value type for .asnLt
    let invalidAsnLtRule = try #require(
      FilterRule(ruleType: .asnLt, value: .invalid(value: "invalid"))
    )
    let state4 = FilterState(rules: [invalidAsnLtRule])
    #expect(state4.asn == .any)
    #expect(state4.remaining.contains(invalidAsnLtRule))
  }

  @Test("Conflicting ASN rules handling")
  func testConflictingAsnRules() throws {
    // Test that conflicting ASN rules are handled (last one wins or goes to remaining)

    // Multiple different ASN rules - behavior should match other filter implementations
    let rules = try [
      #require(FilterRule(ruleType: .asn, value: .number(value: 10))),
      #require(FilterRule(ruleType: .asnGt, value: .number(value: 20))),
    ]

    let state = FilterState(rules: rules)

    // The second rule should either override or both should work
    // Based on other filter patterns, the last one typically wins
    // or conflicting ones go to remaining
    #expect(state.asn == .greaterThan(20) || state.remaining.count > 0)
  }

  @Test("Decode ASN rules from JSON with string values")
  func testDecodeAsnRulesFromJsonStrings() throws {
    // Test decoding ASN rules where values come as strings (as they do from the API)

    // Test .asnIsnull with string "false"
    let asnNotNullJson = """
      {
        "rule_type": 18,
        "value": "false"
      }
      """.data(using: .utf8)!

    let asnNotNullRule = try JSONDecoder().decode(FilterRule.self, from: asnNotNullJson)
    #expect(asnNotNullRule.ruleType == .asnIsnull)
    #expect(asnNotNullRule.value == .boolean(value: false))

    let state1 = FilterState(rules: [asnNotNullRule])
    #expect(state1.asn == .isNotNull)

    // Test .asnIsnull with string "true"
    let asnNullJson = """
      {
        "rule_type": 18,
        "value": "true"
      }
      """.data(using: .utf8)!

    let asnNullRule = try JSONDecoder().decode(FilterRule.self, from: asnNullJson)
    #expect(asnNullRule.ruleType == .asnIsnull)
    #expect(asnNullRule.value == .boolean(value: true))

    let state2 = FilterState(rules: [asnNullRule])
    #expect(state2.asn == .isNull)

    // Test .asn with string "1"
    let asnEqualJson = """
      {
        "rule_type": 2,
        "value": "1"
      }
      """.data(using: .utf8)!

    let asnEqualRule = try JSONDecoder().decode(FilterRule.self, from: asnEqualJson)
    #expect(asnEqualRule.ruleType == .asn)
    #expect(asnEqualRule.value == .number(value: 1))

    let state3 = FilterState(rules: [asnEqualRule])
    #expect(state3.asn == .equalTo(1))

    // Test .asnGt with string "1"
    let asnGtJson = """
      {
        "rule_type": 23,
        "value": "1"
      }
      """.data(using: .utf8)!

    let asnGtRule = try JSONDecoder().decode(FilterRule.self, from: asnGtJson)
    #expect(asnGtRule.ruleType == .asnGt)
    #expect(asnGtRule.value == .number(value: 1))

    let state4 = FilterState(rules: [asnGtRule])
    #expect(state4.asn == .greaterThan(1))

    // Test .asnLt with string "1"
    let asnLtJson = """
      {
        "rule_type": 24,
        "value": "1"
      }
      """.data(using: .utf8)!

    let asnLtRule = try JSONDecoder().decode(FilterRule.self, from: asnLtJson)
    #expect(asnLtRule.ruleType == .asnLt)
    #expect(asnLtRule.value == .number(value: 1))

    let state5 = FilterState(rules: [asnLtRule])
    #expect(state5.asn == .lessThan(1))
  }

  @Test("Encode ASN rules to JSON with string values")
  func testEncodeAsnRulesToJsonStrings() throws {
    // Test that encoding ASN rules produces string values (for API compatibility)

    struct Payload: Decodable {
      var rule_type: Int
      var value: String
    }

    // Test .isNull encoding
    let isNullRule = FilterRule(ruleType: .asnIsnull, value: .boolean(value: true))!
    let isNullJson = try JSONEncoder().encode(isNullRule)
    let isNullPayload = try JSONDecoder().decode(Payload.self, from: isNullJson)
    #expect(isNullPayload.rule_type == 18)
    #expect(isNullPayload.value == "true")

    // Test .isNotNull encoding
    let isNotNullRule = FilterRule(ruleType: .asnIsnull, value: .boolean(value: false))!
    let isNotNullJson = try JSONEncoder().encode(isNotNullRule)
    let isNotNullPayload = try JSONDecoder().decode(Payload.self, from: isNotNullJson)
    #expect(isNotNullPayload.rule_type == 18)
    #expect(isNotNullPayload.value == "false")

    // Test .equalTo encoding
    let equalToRule = FilterRule(ruleType: .asn, value: .number(value: 42))!
    let equalToJson = try JSONEncoder().encode(equalToRule)
    let equalToPayload = try JSONDecoder().decode(Payload.self, from: equalToJson)
    #expect(equalToPayload.rule_type == 2)
    #expect(equalToPayload.value == "42")

    // Test .greaterThan encoding
    let greaterThanRule = FilterRule(ruleType: .asnGt, value: .number(value: 100))!
    let greaterThanJson = try JSONEncoder().encode(greaterThanRule)
    let greaterThanPayload = try JSONDecoder().decode(Payload.self, from: greaterThanJson)
    #expect(greaterThanPayload.rule_type == 23)
    #expect(greaterThanPayload.value == "100")

    // Test .lessThan encoding
    let lessThanRule = FilterRule(ruleType: .asnLt, value: .number(value: 50))!
    let lessThanJson = try JSONEncoder().encode(lessThanRule)
    let lessThanPayload = try JSONDecoder().decode(Payload.self, from: lessThanJson)
    #expect(lessThanPayload.rule_type == 24)
    #expect(lessThanPayload.value == "50")
  }

  @Test("Complete ASN JSON round-trip with string values")
  func testAsnJsonRoundTripWithStrings() throws {
    // Test full round-trip: JSON (string values) -> FilterRule -> FilterState -> FilterRule -> JSON (string values)

    let jsonArray = """
      [
        {
          "rule_type": 18,
          "value": "false"
        },
        {
          "rule_type": 2,
          "value": "42"
        },
        {
          "rule_type": 23,
          "value": "100"
        },
        {
          "rule_type": 24,
          "value": "50"
        }
      ]
      """.data(using: .utf8)!

    // Decode from JSON
    let rules = try JSONDecoder().decode([FilterRule].self, from: jsonArray)
    #expect(rules.count == 4)

    // Test each rule individually to ensure proper decoding
    let notNullRule = rules[0]
    #expect(notNullRule.ruleType == .asnIsnull)
    #expect(notNullRule.value == .boolean(value: false))

    let equalRule = rules[1]
    #expect(equalRule.ruleType == .asn)
    #expect(equalRule.value == .number(value: 42))

    let gtRule = rules[2]
    #expect(gtRule.ruleType == .asnGt)
    #expect(gtRule.value == .number(value: 100))

    let ltRule = rules[3]
    #expect(ltRule.ruleType == .asnLt)
    #expect(ltRule.value == .number(value: 50))

    // Test each rule creates correct FilterState
    // (Note: only one ASN filter can be active at a time, last one wins)
    let state = FilterState(rules: [ltRule])
    #expect(state.asn == .lessThan(50))

    // Encode back to JSON
    let encodedRules = state.rules
    let encodedJson = try JSONEncoder().encode(encodedRules)

    struct Payload: Decodable {
      var rule_type: Int
      var value: String
    }
    let decodedPayload = try JSONDecoder().decode([Payload].self, from: encodedJson)
    #expect(decodedPayload.count == 1)
    #expect(decodedPayload[0].rule_type == 24)
    #expect(decodedPayload[0].value == "50")
  }

  @Test("FilterState with custom field query")
  func testFilterStateWithCustomFieldQuery() throws {
    // Test creating a FilterState with a custom field query
    let customQuery = CustomFieldQuery.expr(8, .exists, .string("true"))

    let state = FilterState.empty.with { $0.customField = customQuery }
    #expect(state.customField == customQuery)

    // Test that the custom field query is preserved when creating from rules
    let rule = try #require(
      FilterRule(ruleType: .customFieldsQuery, value: .customFieldQuery(customQuery)))
    let stateFromRule = FilterState(rules: [rule])

    #expect(stateFromRule.customField == customQuery)
    #expect(stateFromRule.remaining.isEmpty)
  }

  @Test("Convert FilterState custom field query to rule")
  func testFilterStateToRuleCustomFieldQuery() throws {
    // Test that custom field query gets converted to rule
    let customQuery = CustomFieldQuery.expr(8, .exists, .string("true"))
    let state = FilterState.empty.with { $0.customField = customQuery }

    let rules = state.rules
    #expect(rules.count == 1)
    #expect(rules[0].ruleType == .customFieldsQuery)
    #expect(rules[0].value == .customFieldQuery(customQuery))

    // Test round-trip: FilterState -> Rules -> FilterState
    let roundTripState = FilterState(rules: rules)
    #expect(roundTripState.customField == customQuery)
  }

  @Test("Complex rules to FilterState conversion")
  func testRulesToFilterState() throws {
    // @TODO: Add owner and storage path filter

    let input: [FilterRule] = try [
      #require(FilterRule(ruleType: .title, value: .string(value: "shantel"))),
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 66))),
      #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 71))),
      #require(FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: 75))),
      #require(FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))),
      #require(
        FilterRule(
          ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))),
    ]

    let state = FilterState(rules: input)

    #expect(state.tags == .allOf(include: [66, 71], exclude: [75]))

    #expect(state.searchMode == .title)
    #expect(state.searchText == "shantel")
    #expect(state.correspondent == .notAssigned)
    #expect(state.remaining == input.suffix(1))

    #expect(
      state.rules.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
        == input.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
    )
  }

  @Test("Load invalid type preserving functionality")
  func testLoadInvalidTypePreserving() throws {
    // This is a known rule with an invalid value
    let input = """
      {
      "rule_type": 22,
      "value": "7,10,9"
      }
      """.data(using: .utf8)!

    let result = try JSONDecoder().decode(FilterRule.self, from: input)
    #expect(result.ruleType == .hasTagsAny)
    #expect(result.value == .invalid(value: "7,10,9"))

    let output = try JSONEncoder().encode(result)
    struct Payload: Decodable {
      var rule_type: UInt
      var value: String
    }
    let payload = try JSONDecoder().decode(Payload.self, from: output)
    #expect(payload.rule_type == 22)
    #expect(payload.value == "7,10,9")

    let queryItems = FilterRule.queryItems(for: [result])
    #expect(queryItems == [URLQueryItem(name: "tags__id__in", value: "7,10,9")])

    // Multiple ones get properly concatenated "by accident"
    let rule = try #require(FilterRule(ruleType: .hasTagsAny, value: .tag(id: 12)))

    let queryItems2 = FilterRule.queryItems(for: [result, rule])
    #expect(queryItems2 == [URLQueryItem(name: "tags__id__in", value: "12,7,10,9")])
  }

  // - MARK: Date Filter Range Parsing Tests

  @Test("Parse rolling date ranges with numeric intervals")
  func testDateFilterRangeRollingRangeParsing() {
    typealias Range = FilterState.DateFilter.Range

    // Negative numbers with all components
    #expect(Range(rawValue: "[-1 day to now]") == .within(num: -1, interval: .day))
    #expect(Range(rawValue: "[-1 week to now]") == .within(num: -1, interval: .week))
    #expect(Range(rawValue: "[-1 month to now]") == .within(num: -1, interval: .month))
    #expect(Range(rawValue: "[-3 month to now]") == .within(num: -3, interval: .month))
    #expect(Range(rawValue: "[-1 year to now]") == .within(num: -1, interval: .year))
    #expect(Range(rawValue: "[-7 day to now]") == .within(num: -7, interval: .day))

    // Positive numbers
    #expect(Range(rawValue: "[1 day to now]") == .within(num: 1, interval: .day))
    #expect(Range(rawValue: "[3 week to now]") == .within(num: 3, interval: .week))
    #expect(Range(rawValue: "[6 month to now]") == .within(num: 6, interval: .month))
    #expect(Range(rawValue: "[2 year to now]") == .within(num: 2, interval: .year))
  }

  @Test("Parse keyword date ranges")
  func testDateFilterRangeKeywordParsing() {
    typealias Range = FilterState.DateFilter.Range

    #expect(Range(rawValue: "this year") == .currentYear)
    #expect(Range(rawValue: "this month") == .currentMonth)
    #expect(Range(rawValue: "today") == .today)
    #expect(Range(rawValue: "yesterday") == .yesterday)
    #expect(Range(rawValue: "previous week") == .previousWeek)
    #expect(Range(rawValue: "previous month") == .previousMonth)
    #expect(Range(rawValue: "previous quarter") == .previousQuarter)
    #expect(Range(rawValue: "previous year") == .previousYear)
  }

  @Test("Invalid date filter formats return nil")
  func testDateFilterRangeInvalidFormats() {
    typealias Range = FilterState.DateFilter.Range

    // Invalid bracket formats
    #expect(Range(rawValue: "[-1 month]") == nil)  // missing "to now"
    #expect(Range(rawValue: "-1 month to now") == nil)  // missing brackets
    #expect(Range(rawValue: "[1 month to later]") == nil)  // wrong ending

    // Invalid component names
    #expect(Range(rawValue: "[-1 months to now]") == nil)  // plural
    #expect(Range(rawValue: "[-1 decades to now]") == nil)  // invalid component
    #expect(Range(rawValue: "[-1 hour to now]") == nil)  // unsupported component

    // Invalid numbers
    #expect(Range(rawValue: "[abc month to now]") == nil)
    #expect(Range(rawValue: "[- month to now]") == nil)

    // Invalid keyword formats
    #expect(Range(rawValue: "This Year") == nil)  // wrong case
    #expect(Range(rawValue: "TODAY") == nil)  // wrong case
    #expect(Range(rawValue: "last week") == nil)  // wrong keyword

    // Empty and malformed
    #expect(Range(rawValue: "") == nil)
    #expect(Range(rawValue: "[]") == nil)
    #expect(Range(rawValue: "random string") == nil)
  }

  @Test("Date filter ranges round-trip through rawValue")
  func testDateFilterRangeRawValueRoundTrip() {
    typealias Range = FilterState.DateFilter.Range

    // Rolling ranges
    let rolling1 = Range.within(num: -3, interval: .month)
    #expect(rolling1.rawValue == "[-3 month to now]")
    #expect(Range(rawValue: rolling1.rawValue) == rolling1)

    let rolling2 = Range.within(num: 7, interval: .day)
    #expect(rolling2.rawValue == "[7 day to now]")
    #expect(Range(rawValue: rolling2.rawValue) == rolling2)

    // Keywords
    let keyword1 = Range.today
    #expect(keyword1.rawValue == "today")
    #expect(Range(rawValue: keyword1.rawValue) == keyword1)

    let keyword2 = Range.previousMonth
    #expect(keyword2.rawValue == "previous month")
    #expect(Range(rawValue: keyword2.rawValue) == keyword2)
  }
}
