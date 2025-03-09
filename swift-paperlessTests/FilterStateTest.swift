//
//  FilterStateTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 02.04.23.
//

import DataModel
import Foundation
import Testing

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

@Suite
struct FilterStateTest {
    // - MARK: FilterRule to FilterState

    @Test
    func testSearchModeConversion() {
        #expect(FilterRuleType.title == FilterState.SearchMode.title.ruleType)
        #expect(FilterRuleType.content == FilterState.SearchMode.content.ruleType)
        #expect(FilterRuleType.titleContent == FilterState.SearchMode.titleContent.ruleType)

        #expect(FilterState.SearchMode(ruleType: .title) == FilterState.SearchMode.title)
        #expect(FilterState.SearchMode(ruleType: .content) == FilterState.SearchMode.content)
        #expect(FilterState.SearchMode(ruleType: .titleContent) == FilterState.SearchMode.titleContent)
    }

    @Test
    func testRuleToFilterStateTextSearch() {
        for mode in [FilterRuleType](
            [.title, .content, .titleContent])
        {
            let state = FilterState(rules: [
                .init(ruleType: mode, value: .string(value: "hallo")),
            ])
            #expect(state == FilterState.default.with {
                $0.searchText = "hallo"
                $0.searchMode = .init(ruleType: mode)!
            }
            )
            #expect(state.remaining.isEmpty)
        }
    }

    @Test
    func testRuleToFilterStateCorrespondent() {
        // Old single rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: 8)),
            ]) ==
                FilterState.default.with { $0.correspondent = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            ]) ==
                FilterState.default.with { $0.correspondent = .notAssigned }
        )

        // New anyOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
            ]) ==
                FilterState.default.with { $0.correspondent = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19)),
            ]) ==
                FilterState.default.with { $0.correspondent = .anyOf(ids: [8, 19]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasCorrespondentAny, value: .invalid(value: "11,12"))]).correspondent ==
            .anyOf(ids: [11, 12]))

        // New noneOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
            ]) ==
                FilterState.default.with { $0.correspondent = .noneOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 19)),
            ]) ==
                FilterState.default.with { $0.correspondent = .noneOf(ids: [8, 19]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .doesNotHaveCorrespondent, value: .invalid(value: "11,12"))]).correspondent ==
            .noneOf(ids: [11, 12]))

        // @TODO: Test error states
    }

    @Test
    func testRuleToFilterStateDocumentType() {
        // Old single rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: 8)),
            ]) ==
                FilterState.default.with { $0.documentType = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: nil)),
            ]) ==
                FilterState.default.with { $0.documentType = .notAssigned }
        )

        // New anyOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            ]) ==
                FilterState.default.with { $0.documentType = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19)),
            ]) ==
                FilterState.default.with { $0.documentType = .anyOf(ids: [8, 19]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasDocumentTypeAny, value: .invalid(value: "11,12"))]).documentType ==
            .anyOf(ids: [11, 12]))

        // New noneOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            ]) ==
                FilterState.default.with { $0.documentType = .noneOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 19)),
            ]) ==
                FilterState.default.with { $0.documentType = .noneOf(ids: [8, 19]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .doesNotHaveDocumentType, value: .invalid(value: "11,12"))]).documentType ==
            .noneOf(ids: [11, 12]))

        // @TODO: Test error states
    }

    @Test
    func testRuleToFilterStateRemaining() {
        // Unsupported rules go to "remaining":
        let addedAfter = FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
        #expect(
            FilterState(rules: [addedAfter]).remaining ==
                [addedAfter]
        )
    }

    @Test
    func testRuleToFilterStateTags() {
        let tagAll = [FilterRule]([
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
        ])

        // Single tag all rule
        #expect(
            FilterState(rules: Array(tagAll.prefix(1))) ==
                FilterState.default.with { $0.tags = .allOf(include: [66], exclude: []) }
        )

        #expect(
            FilterState(rules: Array(tagAll.prefix(2))) ==
                FilterState.default.with { $0.tags = .allOf(include: [66, 71], exclude: []) }
        )

        #expect(
            FilterState(rules: tagAll) ==
                FilterState.default.with { $0.tags = .allOf(include: [66, 71], exclude: [75]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasTagsAll, value: .invalid(value: "11,12"))]).tags ==
            .allOf(include: [11, 12], exclude: []))

        #expect(FilterState(rules: [FilterRule(ruleType: .doesNotHaveTag, value: .invalid(value: "11,12"))]).tags ==
            .allOf(include: [], exclude: [11, 12]))

        #expect(
            FilterState(rules: Array(tagAll.suffix(1))) ==
                FilterState.default.with { $0.tags = .allOf(include: [], exclude: [75]) }
        )

        #expect(
            FilterState(rules: Array(tagAll.reversed())) ==
                FilterState.default.with { $0.tags = .allOf(include: [71, 66], exclude: [75]) }
        )

        let tagAny = [FilterRule]([
            .init(ruleType: .hasTagsAny, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAny, value: .tag(id: 71)),
        ])

        #expect(
            FilterState(rules: Array(tagAny.prefix(1))) ==
                FilterState.default.with { $0.tags = .anyOf(ids: [66]) }
        )

        #expect(
            FilterState(rules: tagAny) ==
                FilterState.default.with { $0.tags = .anyOf(ids: [66, 71]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasTagsAny, value: .invalid(value: "11,12"))]).tags ==
            .anyOf(ids: [11, 12]))

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasAnyTag, value: .boolean(value: false)),
            ]) ==
                FilterState.default.with { $0.tags = .notAssigned }
        )

        // @TODO: Test error states
    }

    @Test
    func testRuleToFilterStateOwner() {
        #expect(
            FilterState(rules: [
                .init(ruleType: .owner, value: .number(value: 8)),
            ]) ==
                FilterState.default.with { $0.owner = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerIsnull, value: .boolean(value: true)),
            ]) ==
                FilterState.default.with { $0.owner = .notAssigned }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerIsnull, value: .boolean(value: false)), // this is pretty odd
            ]) ==
                FilterState.default.with { $0.owner = .any }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerAny, value: .number(value: 8)),
            ]) ==
                FilterState.default.with { $0.owner = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerAny, value: .number(value: 8)),
                .init(ruleType: .ownerAny, value: .number(value: 99)),
            ]) ==
                FilterState.default.with { $0.owner = .anyOf(ids: [8, 99]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .ownerAny, value: .invalid(value: "11,12"))]).owner ==
            .anyOf(ids: [11, 12]))

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
            ]) ==
                FilterState.default.with { $0.owner = .noneOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
                .init(ruleType: .ownerDoesNotInclude, value: .number(value: 99)),
            ]) ==
                FilterState.default.with { $0.owner = .noneOf(ids: [8, 99]) }
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .ownerDoesNotInclude, value: .invalid(value: "11,12"))]).owner ==
            .noneOf(ids: [11, 12]))

        // @TODO: Test error states
    }

    func testRuleToFilterStateStoragePath() {
        // Old single rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .storagePath, value: .storagePath(id: 8)),
            ]) ==
                FilterState.default.with { $0.storagePath = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .storagePath, value: .storagePath(id: nil)),
            ]) ==
                FilterState.default.with { $0.storagePath = .notAssigned }
        )

        // New anyOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            ]) ==
                FilterState.default.with { $0.storagePath = .anyOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 19)),
            ]) ==
                FilterState.default.with { $0.storagePath = .anyOf(ids: [8, 19]) }
        )

        #expect(FilterState(rules: [FilterRule(ruleType: .hasStoragePathAny, value: .invalid(value: "11,12"))]).storagePath ==
            .anyOf(ids: [11, 12]))

        // New noneOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            ]) ==
                FilterState.default.with { $0.storagePath = .noneOf(ids: [8]) }
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 19)),
            ]) ==
                FilterState.default.with { $0.storagePath = .noneOf(ids: [8, 19]) }
        )

        #expect(FilterState(rules: [FilterRule(ruleType: .doesNotHaveStoragePath, value: .invalid(value: "11,12"))]).storagePath ==
            .noneOf(ids: [11, 12]))

        // @TODO: Test error states
    }

    // - MARK: FilterState to FilterRule

    @Test
    func testFilterStateToRuleTextSearch() {
        for mode in [FilterState.SearchMode](
            [.title, .content, .titleContent])
        {
            let state = FilterState.default.with { $0.searchText = "hallo"
                $0.searchMode = mode
            }

            #expect(state.rules == [
                FilterRule(ruleType: mode.ruleType, value: .string(value: "hallo")),
            ])
        }
    }

    @Test
    func testFilterStateToRuleEmpty() {
        #expect(FilterState.default.rules == [])
    }

    @Test
    func testFilterStateToRuleCorrespondent() {
        // Old single rule
        #expect(
            [FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))] ==
                FilterState.default.with { $0.correspondent = .notAssigned }.rules
        )

        // New anyOf rule
        #expect(
            [FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8))] ==
                FilterState.default.with { $0.correspondent = .anyOf(ids: [8]) }.rules
        )

        #expect(
            [
                FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
                FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 99)),
            ] ==
                FilterState.default.with { $0.correspondent = .anyOf(ids: [8, 99]) }.rules
        )

        // New noneOf rule
        #expect(
            [FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8))] ==
                FilterState.default.with { $0.correspondent = .noneOf(ids: [8]) }.rules
        )

        #expect(
            [
                FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
                FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 99)),
            ] ==
                FilterState.default.with { $0.correspondent = .noneOf(ids: [8, 99]) }.rules
        )
    }

    @Test
    func testFilterStateToRuleDocumentType() {
        // Old single rule
        #expect(
            [FilterRule(ruleType: .documentType, value: .documentType(id: nil))] ==
                FilterState.default.with { $0.documentType = .notAssigned }.rules
        )

        // New anyOf rule
        #expect(
            [FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8))] ==
                FilterState.default.with { $0.documentType = .anyOf(ids: [8]) }.rules
        )

        #expect([
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 99)),
        ] == FilterState.default.with { $0.documentType = .anyOf(ids: [8, 99]) }.rules)

        // New noneOf rule
        #expect([
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
        ] == FilterState.default.with { $0.documentType = .noneOf(ids: [8]) }.rules)

        #expect([
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 99)),
        ] == FilterState.default.with { $0.documentType = .noneOf(ids: [8, 99]) }.rules)
    }

    @Test
    func testFilterStatetoRuleRemaining() {
        // Unsupported rules go to "remaining" and are preserved
        let addedAfter = FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
        #expect(
            FilterState(rules: [addedAfter]).rules ==
                [addedAfter]
        )
    }

    @Test
    func testFilterStateToRuleTags() {
        let tagAll = [FilterRule]([
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
        ])

        #expect(
            tagAll ==
                FilterState.default.with { $0.tags = .allOf(include: [66, 71], exclude: [75]) }.rules
        )

        let tagAny = [FilterRule]([
            .init(ruleType: .hasTagsAny, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAny, value: .tag(id: 71)),
        ])

        #expect(
            tagAny ==
                FilterState.default.with { $0.tags = .anyOf(ids: [66, 71]) }.rules
        )

        #expect(
            [FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false))] ==
                FilterState.default.with { $0.tags = .notAssigned }.rules
        )
    }

    @Test
    func testFilterStateToRuleOwner() {
        #expect([
            FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true)),
        ] == FilterState.default.with { $0.owner = .notAssigned }.rules)

        // This could theoretically be expressed as:
        // FilterRule(ruleType: .ownerIsnull, value: .boolean(value: false))
        // But this is redundant to just not having a rule, so let's not create one.
        #expect(FilterState.default.with { $0.owner = .any }.rules == []) // we could the

        #expect([
            FilterRule(ruleType: .ownerAny, value: .number(value: 8)),
        ] == FilterState.default.with { $0.owner = .anyOf(ids: [8]) }.rules)

        // Technically, this could also be expressed as a rule .owner with value 8,
        // but that's equivalent

        #expect([
            FilterRule(ruleType: .ownerAny, value: .number(value: 8)),
            FilterRule(ruleType: .ownerAny, value: .number(value: 99)),
        ] == FilterState.default.with { $0.owner = .anyOf(ids: [8, 99]) }.rules)

        #expect([
            FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
        ] == FilterState.default.with { $0.owner = .noneOf(ids: [8]) }.rules)

        #expect([
            FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
            FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 99)),
        ] == FilterState.default.with { $0.owner = .noneOf(ids: [8, 99]) }.rules)
    }

    @Test
    func testFilterStateToRuleStoragePath() {
        // Old single rule
        #expect(
            [FilterRule(ruleType: .storagePath, value: .storagePath(id: nil))] ==
                FilterState.default.with { $0.storagePath = .notAssigned }.rules
        )

        // New anyOf rule
        #expect(
            [FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8))] ==
                FilterState.default.with { $0.storagePath = .anyOf(ids: [8]) }.rules
        )

        #expect([
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 99)),
        ] == FilterState.default.with { $0.storagePath = .anyOf(ids: [8, 99]) }.rules)

        // New noneOf rule
        #expect([
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
        ] == FilterState.default.with { $0.storagePath = .noneOf(ids: [8]) }.rules)

        #expect([
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 99)),
        ] == FilterState.default.with { $0.storagePath = .noneOf(ids: [8, 99]) }.rules)
    }

    @Test
    func testRulesToFilterState() throws {
        // @TODO: Add owner and storage path filter

        let input: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1))),
        ]

        // let state = FilterState.default.with {$0.rules = input}
        let state = FilterState(rules: input)

        #expect(state.tags == .allOf(include: [66, 71], exclude: [75]))

        #expect(state.searchMode == .title)
        #expect(state.searchText == "shantel")
        #expect(state.correspondent == .notAssigned)
        #expect(state.remaining == input.suffix(1))

        #expect(
            state.rules.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue }) ==
                input.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue })
        )
    }

    @Test
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
        let rule = FilterRule(ruleType: .hasTagsAny, value: .tag(id: 12))

        let queryItems2 = FilterRule.queryItems(for: [result, rule])
        #expect(queryItems2 == [URLQueryItem(name: "tags__id__in", value: "12,7,10,9")])
    }
}
