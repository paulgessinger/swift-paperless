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
}
