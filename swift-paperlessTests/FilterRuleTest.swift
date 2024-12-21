//
//  FilterRuleTest.swift
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

struct DecodeHelper: Codable, Equatable {
    let rule_type: Int
    let value: String?
}

@Suite
struct FilterRuleTest {
    @Test
    func testDecoding() throws {
        let input = """
        {
          "rule_type": 19,
          "value": "shantel"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(FilterRule.self, from: input)
        #expect(result == FilterRule(ruleType: .titleContent, value: .string(value: "shantel")))
    }

    @Test
    func testDecodingUnknown() throws {
        let input = """
        {
          "rule_type": 9999,
          "value": "1234"
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(FilterRule.self, from: input)
        #expect(result == FilterRule(ruleType: .other(9999), value: .string(value: "1234")))
    }

    @Test
    func testDecodingMultiple() throws {
        let input = """
        [
            {
                "rule_type": 0,
                "value": "shantel"
            },
            {
                "rule_type": 6,
                "value": "66"
            },
            {
                "rule_type": 6,
                "value": "71"
            },
            {
                "rule_type": 17,
                "value": "75"
            },
            {
                "rule_type": 3,
                "value": null
            },
            {
                "rule_type": 14,
                "value": "2023-01-01"
            }
        ]
        """.data(using: .utf8)!

        let result = try makeDecoder(tz: .init(abbreviation: "UTC")!).decode([FilterRule].self, from: input)

        let expected: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1))),
        ]

        #expect(result == expected)
    }

    @Test
    func testEncoding() throws {
        let input = FilterRule(ruleType: .hasTagsAll, value: .tag(id: 6))

        let data = try JSONEncoder().encode(input)

        let dict = try JSONDecoder().decode(DecodeHelper.self, from: data)

        #expect(dict == DecodeHelper(rule_type: 6, value: "6"))
    }

    @Test
    func testEncodingMultiple() throws {
        let input: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1))),
        ]

        let encoder = JSONEncoder()
        let actual = try JSONDecoder().decode([DecodeHelper].self, from: encoder.encode(input))

        let expected: [DecodeHelper] = [
            .init(rule_type: 0, value: "shantel"),
            .init(rule_type: 6, value: "66"),
            .init(rule_type: 6, value: "71"),
            .init(rule_type: 17, value: "75"),
            .init(rule_type: 3, value: nil),
            .init(rule_type: 14, value: "2023-01-01"),
        ]

        #expect(actual == expected)
    }

    @Test
    func testQueryItems() throws {
        let input: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1))),
            .init(ruleType: .storagePath, value: .storagePath(id: 8)),
            .init(ruleType: .storagePath, value: .storagePath(id: nil)),
        ]

        let sort = { (a: URLQueryItem, b: URLQueryItem) -> Bool in a.name < b.name }

        var items = FilterRule.queryItems(for: input)
        items.sort(by: sort)

        var expected: [URLQueryItem] = [
            .init(name: "title__icontains", value: "shantel"),
            .init(name: "tags__id__all", value: "66,71"),
            .init(name: "tags__id__none", value: "75"),
            .init(name: "correspondent__isnull", value: "1"),
            .init(name: "added__date__gt", value: "2023-01-01"),
            .init(name: "storage_path__id", value: "8"),
            .init(name: "storage_path__isnull", value: "1"),
        ]
        expected.sort(by: sort)

//        #expect(items[0], expected[0])
        for (item, exp) in zip(items, expected) {
            #expect(item == exp)
        }

        #expect(
            [URLQueryItem(name: "is_tagged", value: "0")] ==
                FilterRule.queryItems(for: [.init(ruleType: .hasAnyTag, value: .boolean(value: false))])
        )
    }

    @Test
    func testFilterOwner() throws {
        let input1 = FilterRule(ruleType: .owner, value: .owner(id: 8))
        let items = FilterRule.queryItems(for: [input1])
        #expect(items == [URLQueryItem(name: "owner__id", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .ownerAny, value: .owner(id: 8)),
        ]) == [URLQueryItem(name: "owner__id__in", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .ownerAny, value: .owner(id: 8)),
            FilterRule(ruleType: .ownerAny, value: .owner(id: 19)),
        ]) == [URLQueryItem(name: "owner__id__in", value: "19,8")])

        #expect(FilterRule.queryItems(for: [
            .init(ruleType: .ownerIsnull, value: .boolean(value: true)),
        ]) == [URLQueryItem(name: "owner__isnull", value: "1")])

        #expect(FilterRule.queryItems(for: [
            .init(ruleType: .ownerDoesNotInclude, value: .owner(id: 25)),
        ]) == [URLQueryItem(name: "owner__id__none", value: "25")])

        #expect(FilterRule.queryItems(for: [
            .init(ruleType: .ownerDoesNotInclude, value: .owner(id: 25)),
            .init(ruleType: .ownerDoesNotInclude, value: .owner(id: 99)),
        ]) == [URLQueryItem(name: "owner__id__none", value: "25,99")])
    }

    @Test
    func testFilterDocumentType() throws {
        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .documentType, value: .documentType(id: 8)),
        ]) == [URLQueryItem(name: "document_type__id", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
        ]) == [URLQueryItem(name: "document_type__id__in", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19)),
        ]) == [URLQueryItem(name: "document_type__id__in", value: "19,8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
        ]) == [URLQueryItem(name: "document_type__id__none", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 87)),
        ]) == [URLQueryItem(name: "document_type__id__none", value: "8,87")])
    }

    @Test
    func testCorrespondent() throws {
        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .correspondent, value: .correspondent(id: 8)),
        ]) == [URLQueryItem(name: "correspondent__id", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
        ]) == [URLQueryItem(name: "correspondent__id__in", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
            FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19)),
        ]) == [URLQueryItem(name: "correspondent__id__in", value: "19,8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
        ]) == [URLQueryItem(name: "correspondent__id__none", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
            FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 87)),
        ]) == [URLQueryItem(name: "correspondent__id__none", value: "8,87")])
    }

    @Test
    func testStoragePath() throws {
        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .storagePath, value: .storagePath(id: 8)),
        ]) == [URLQueryItem(name: "storage_path__id", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
        ]) == [URLQueryItem(name: "storage_path__id__in", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 19)),
        ]) == [URLQueryItem(name: "storage_path__id__in", value: "19,8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
        ]) == [URLQueryItem(name: "storage_path__id__none", value: "8")])

        #expect(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 87)),
        ]) == [URLQueryItem(name: "storage_path__id__none", value: "8,87")])
    }

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
            #expect(state ==
                .init(
                    searchText: "hallo",
                    searchMode: .init(ruleType: mode)!
                ))
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
                FilterState(correspondent: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            ]) ==
                FilterState(correspondent: .notAssigned)
        )

        // New anyOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
            ]) ==
                FilterState(correspondent: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19)),
            ]) ==
                FilterState(correspondent: .anyOf(ids: [8, 19]))
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasCorrespondentAny, value: .invalid(value: "11,12"))]).correspondent ==
            .anyOf(ids: [11, 12]))

        // New noneOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
            ]) ==
                FilterState(correspondent: .noneOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 19)),
            ]) ==
                FilterState(correspondent: .noneOf(ids: [8, 19]))
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
                FilterState(documentType: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: nil)),
            ]) ==
                FilterState(documentType: .notAssigned)
        )

        // New anyOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            ]) ==
                FilterState(documentType: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19)),
            ]) ==
                FilterState(documentType: .anyOf(ids: [8, 19]))
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasDocumentTypeAny, value: .invalid(value: "11,12"))]).documentType ==
            .anyOf(ids: [11, 12]))

        // New noneOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            ]) ==
                FilterState(documentType: .noneOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 19)),
            ]) ==
                FilterState(documentType: .noneOf(ids: [8, 19]))
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
                FilterState(tags: .allOf(include: [66], exclude: []))
        )

        #expect(
            FilterState(rules: Array(tagAll.prefix(2))) ==
                FilterState(tags: .allOf(include: [66, 71], exclude: []))
        )

        #expect(
            FilterState(rules: tagAll) ==
                FilterState(tags: .allOf(include: [66, 71], exclude: [75]))
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasTagsAll, value: .invalid(value: "11,12"))]).tags ==
            .allOf(include: [11, 12], exclude: []))

        #expect(FilterState(rules: [FilterRule(ruleType: .doesNotHaveTag, value: .invalid(value: "11,12"))]).tags ==
            .allOf(include: [], exclude: [11, 12]))

        #expect(
            FilterState(rules: Array(tagAll.suffix(1))) ==
                FilterState(tags: .allOf(include: [], exclude: [75]))
        )

        #expect(
            FilterState(rules: Array(tagAll.reversed())) ==
                FilterState(tags: .allOf(include: [71, 66], exclude: [75]))
        )

        let tagAny = [FilterRule]([
            .init(ruleType: .hasTagsAny, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAny, value: .tag(id: 71)),
        ])

        #expect(
            FilterState(rules: Array(tagAny.prefix(1))) ==
                FilterState(tags: .anyOf(ids: [66]))
        )

        #expect(
            FilterState(rules: tagAny) ==
                FilterState(tags: .anyOf(ids: [66, 71]))
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .hasTagsAny, value: .invalid(value: "11,12"))]).tags ==
            .anyOf(ids: [11, 12]))

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasAnyTag, value: .boolean(value: false)),
            ]) ==
                FilterState(tags: .notAssigned)
        )

        // @TODO: Test error states
    }

    @Test
    func testRuleToFilterStateOwner() {
        #expect(
            FilterState(rules: [
                .init(ruleType: .owner, value: .number(value: 8)),
            ]) ==
                FilterState(owner: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerIsnull, value: .boolean(value: true)),
            ]) ==
                FilterState(owner: .notAssigned)
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerIsnull, value: .boolean(value: false)), // this is pretty odd
            ]) ==
                FilterState(owner: .any)
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerAny, value: .number(value: 8)),
            ]) ==
                FilterState(owner: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerAny, value: .number(value: 8)),
                .init(ruleType: .ownerAny, value: .number(value: 99)),
            ]) ==
                FilterState(owner: .anyOf(ids: [8, 99]))
        )

        // Invalid multi-value recovery
        #expect(FilterState(rules: [FilterRule(ruleType: .ownerAny, value: .invalid(value: "11,12"))]).owner ==
            .anyOf(ids: [11, 12]))

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
            ]) ==
                FilterState(owner: .noneOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
                .init(ruleType: .ownerDoesNotInclude, value: .number(value: 99)),
            ]) ==
                FilterState(owner: .noneOf(ids: [8, 99]))
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
                FilterState(storagePath: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .storagePath, value: .storagePath(id: nil)),
            ]) ==
                FilterState(storagePath: .notAssigned)
        )

        // New anyOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            ]) ==
                FilterState(storagePath: .anyOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 19)),
            ]) ==
                FilterState(storagePath: .anyOf(ids: [8, 19]))
        )

        #expect(FilterState(rules: [FilterRule(ruleType: .hasStoragePathAny, value: .invalid(value: "11,12"))]).storagePath ==
            .anyOf(ids: [11, 12]))

        // New noneOf rule
        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            ]) ==
                FilterState(storagePath: .noneOf(ids: [8]))
        )

        #expect(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 19)),
            ]) ==
                FilterState(storagePath: .noneOf(ids: [8, 19]))
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
            let state = FilterState(searchText: "hallo", searchMode: mode)

            #expect(state.rules == [
                FilterRule(ruleType: mode.ruleType, value: .string(value: "hallo")),
            ])
        }
    }

    @Test
    func testFilterStateToRuleEmpty() {
        #expect(FilterState().rules == [])
    }

    @Test
    func testFilterStateToRuleCorrespondent() {
        // Old single rule
        #expect(
            [FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))] ==
                FilterState(correspondent: .notAssigned).rules
        )

        // New anyOf rule
        #expect(
            [FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8))] ==
                FilterState(correspondent: .anyOf(ids: [8])).rules
        )

        #expect(
            [
                FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
                FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 99)),
            ] ==
                FilterState(correspondent: .anyOf(ids: [8, 99])).rules
        )

        // New noneOf rule
        #expect(
            [FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8))] ==
                FilterState(correspondent: .noneOf(ids: [8])).rules
        )

        #expect(
            [
                FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
                FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 99)),
            ] ==
                FilterState(correspondent: .noneOf(ids: [8, 99])).rules
        )
    }

    @Test
    func testFilterStateToRuleDocumentType() {
        // Old single rule
        #expect(
            [FilterRule(ruleType: .documentType, value: .documentType(id: nil))] ==
                FilterState(documentType: .notAssigned).rules
        )

        // New anyOf rule
        #expect(
            [FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8))] ==
                FilterState(documentType: .anyOf(ids: [8])).rules
        )

        #expect([
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 99)),
        ] == FilterState(documentType: .anyOf(ids: [8, 99])).rules)

        // New noneOf rule
        #expect([
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
        ] == FilterState(documentType: .noneOf(ids: [8])).rules)

        #expect([
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 99)),
        ] == FilterState(documentType: .noneOf(ids: [8, 99])).rules)
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
                FilterState(tags: .allOf(include: [66, 71], exclude: [75])).rules
        )

        let tagAny = [FilterRule]([
            .init(ruleType: .hasTagsAny, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAny, value: .tag(id: 71)),
        ])

        #expect(
            tagAny ==
                FilterState(tags: .anyOf(ids: [66, 71])).rules
        )

        #expect(
            [FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false))] ==
                FilterState(tags: .notAssigned).rules
        )
    }

    @Test
    func testFilterStateToRuleOwner() {
        #expect([
            FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true)),
        ] == FilterState(owner: .notAssigned).rules)

        // This could theoretically be expressed as:
        // FilterRule(ruleType: .ownerIsnull, value: .boolean(value: false))
        // But this is redundant to just not having a rule, so let's not create one.
        #expect(FilterState(owner: .any).rules == []) // we could the

        #expect([
            FilterRule(ruleType: .ownerAny, value: .number(value: 8)),
        ] == FilterState(owner: .anyOf(ids: [8])).rules)

        // Technically, this could also be expressed as a rule .owner with value 8,
        // but that's equivalent

        #expect([
            FilterRule(ruleType: .ownerAny, value: .number(value: 8)),
            FilterRule(ruleType: .ownerAny, value: .number(value: 99)),
        ] == FilterState(owner: .anyOf(ids: [8, 99])).rules)

        #expect([
            FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
        ] == FilterState(owner: .noneOf(ids: [8])).rules)

        #expect([
            FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 8)),
            FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: 99)),
        ] == FilterState(owner: .noneOf(ids: [8, 99])).rules)
    }

    @Test
    func testFilterStateToRuleStoragePath() {
        // Old single rule
        #expect(
            [FilterRule(ruleType: .storagePath, value: .storagePath(id: nil))] ==
                FilterState(storagePath: .notAssigned).rules
        )

        // New anyOf rule
        #expect(
            [FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8))] ==
                FilterState(storagePath: .anyOf(ids: [8])).rules
        )

        #expect([
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 99)),
        ] == FilterState(storagePath: .anyOf(ids: [8, 99])).rules)

        // New noneOf rule
        #expect([
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
        ] == FilterState(storagePath: .noneOf(ids: [8])).rules)

        #expect([
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 99)),
        ] == FilterState(storagePath: .noneOf(ids: [8, 99])).rules)
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
    func testLoadSavedView() throws {
        let input = """
        {
          "count": 4,
          "next": null,
          "previous": null,
          "results": [
            {
              "id": 3,
              "name": "CHEP 2023 & CERN",
              "show_on_dashboard": false,
              "show_in_sidebar": true,
              "sort_field": "created",
              "sort_reverse": true,
              "filter_rules": [
                {
                  "rule_type": 0,
                  "value": "shantel"
                },
                {
                  "rule_type": 6,
                  "value": "66"
                },
                {
                  "rule_type": 6,
                  "value": "71"
                },
                {
                  "rule_type": 17,
                  "value": "75"
                },
                {
                  "rule_type": 3,
                  "value": null
                },
                {
                  "rule_type": 14,
                  "value": "2023-01-01"
                }
              ]
            },
            {
              "id": 2,
              "name": "Health",
              "show_on_dashboard": false,
              "show_in_sidebar": true,
              "sort_field": "created",
              "sort_reverse": true,
              "filter_rules": [
                {
                  "rule_type": 6,
                  "value": "9"
                }
              ]
            },
            {
              "id": 1,
              "name": "Inbox",
              "show_on_dashboard": true,
              "show_in_sidebar": true,
              "sort_field": "added",
              "sort_reverse": true,
              "filter_rules": [
                {
                  "rule_type": 6,
                  "value": "1"
                }
              ]
            },
            {
              "id": 4,
              "name": "Without any tag",
              "show_on_dashboard": false,
              "show_in_sidebar": true,
              "sort_field": "created",
              "sort_reverse": true,
              "filter_rules": [
                {
                  "rule_type": 7,
                  "value": "false"
                }
              ]
            }
          ]
        }
        """

        let result = try JSONDecoder().decode(ListResponse<SavedView>.self, from: input.data(using: .utf8)!)
        print(result)
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
