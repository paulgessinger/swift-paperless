//
//  FilterRuleTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 02.04.23.
//

import XCTest

private func datetime(year: Int, month: Int, day: Int) -> Date {
    var dateComponents = DateComponents()
    dateComponents.year = year
    dateComponents.month = month
    dateComponents.day = day
    dateComponents.timeZone = TimeZone(abbreviation: "UTC")
    dateComponents.hour = 0
    dateComponents.minute = 0

    return Calendar(identifier: .gregorian).date(from: dateComponents)!
}

final class FilterRuleTest: XCTestCase {
    func testDecoding() throws {
        let input = """
        {
          "rule_type": 19,
          "value": "shantel"
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(FilterRule.self, from: input)
        XCTAssertEqual(result, FilterRule(ruleType: .titleContent, value: .string(value: "shantel")))
    }

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

        let result = try JSONDecoder().decode([FilterRule].self, from: input)

        let expected: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1))),
        ]

        XCTAssertEqual(result, expected)
    }

    func testEncoding() throws {
        let input = FilterRule(ruleType: .hasTagsAll, value: .tag(id: 6))

        let data = try String(data: JSONEncoder().encode(input), encoding: .utf8)!

        XCTAssertEqual(data, "{\"rule_type\":6,\"value\":\"6\"}")
    }

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
        let actual = try String(data: encoder.encode(input), encoding: .utf8)!

        let expected = """
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
        """
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\n", with: "")

        XCTAssertEqual(actual, expected)
    }

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

//        XCTAssertEqual(items[0], expected[0])
        for (item, exp) in zip(items, expected) {
            XCTAssertEqual(item, exp)
        }

        XCTAssertEqual(
            [URLQueryItem(name: "is_tagged", value: "0")],
            FilterRule.queryItems(for: [.init(ruleType: .hasAnyTag, value: .boolean(value: false))]))
    }

    func testFilterOwner() throws {
        let input1 = FilterRule(ruleType: .owner, value: .owner(id: 8))
        let items = FilterRule.queryItems(for: [input1])
        XCTAssertEqual(items, [URLQueryItem(name: "owner__id", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .ownerAny, value: .owner(id: 8)),
        ]), [URLQueryItem(name: "owner__id__in", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .ownerAny, value: .owner(id: 8)),
            FilterRule(ruleType: .ownerAny, value: .owner(id: 19)),
        ]), [URLQueryItem(name: "owner__id__in", value: "19,8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            .init(ruleType: .ownerIsnull, value: .boolean(value: true)),
        ]), [URLQueryItem(name: "owner__isnull", value: "1")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            .init(ruleType: .ownerDoesNotInclude, value: .owner(id: 25)),
        ]), [URLQueryItem(name: "owner__id__none", value: "25")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            .init(ruleType: .ownerDoesNotInclude, value: .owner(id: 25)),
            .init(ruleType: .ownerDoesNotInclude, value: .owner(id: 99)),
        ]), [URLQueryItem(name: "owner__id__none", value: "25,99")])
    }

    func testFilterDocumentType() throws {
        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .documentType, value: .documentType(id: 8)),
        ]), [URLQueryItem(name: "document_type__id", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
        ]), [URLQueryItem(name: "document_type__id__in", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19)),
        ]), [URLQueryItem(name: "document_type__id__in", value: "19,8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
        ]), [URLQueryItem(name: "document_type__id__none", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 87)),
        ]), [URLQueryItem(name: "document_type__id__none", value: "8,87")])
    }

    func testCorrespondent() throws {
        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .correspondent, value: .correspondent(id: 8)),
        ]), [URLQueryItem(name: "correspondent__id", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
        ]), [URLQueryItem(name: "correspondent__id__in", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
            FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19)),
        ]), [URLQueryItem(name: "correspondent__id__in", value: "19,8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
        ]), [URLQueryItem(name: "correspondent__id__none", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
            FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 87)),
        ]), [URLQueryItem(name: "correspondent__id__none", value: "8,87")])
    }

    func testStoragePath() throws {
        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .storagePath, value: .storagePath(id: 8)),
        ]), [URLQueryItem(name: "storage_path__id", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
        ]), [URLQueryItem(name: "storage_path__id__in", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 19)),
        ]), [URLQueryItem(name: "storage_path__id__in", value: "19,8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
        ]), [URLQueryItem(name: "storage_path__id__none", value: "8")])

        XCTAssertEqual(FilterRule.queryItems(for: [
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 87)),
        ]), [URLQueryItem(name: "storage_path__id__none", value: "8,87")])
    }

    // - MARK: FilterRule to FilterState

    func testSearchModeConversion() {
        XCTAssertEqual(FilterRuleType.title, FilterState.SearchMode.title.ruleType)
        XCTAssertEqual(FilterRuleType.content, FilterState.SearchMode.content.ruleType)
        XCTAssertEqual(FilterRuleType.titleContent, FilterState.SearchMode.titleContent.ruleType)

        XCTAssertEqual(FilterState.SearchMode(ruleType: .title), FilterState.SearchMode.title)
        XCTAssertEqual(FilterState.SearchMode(ruleType: .content), FilterState.SearchMode.content)
        XCTAssertEqual(FilterState.SearchMode(ruleType: .titleContent), FilterState.SearchMode.titleContent)
    }

    func testRuleToFilterStateTextSearch() {
        for mode in [FilterRuleType](
            [.title, .content, .titleContent])
        {
            let state = FilterState(rules: [
                .init(ruleType: mode, value: .string(value: "hallo")),
            ])
            XCTAssertEqual(state,
                           .init(
                               searchText: "hallo",
                               searchMode: .init(ruleType: mode)!))
            XCTAssert(state.remaining.isEmpty)
        }
    }

    func testRuleToFilterStateCorrespondent() {
        // Old single rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: 8)),
            ]),
            FilterState(correspondent: .anyOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            ]),
            FilterState(correspondent: .notAssigned))

        // New anyOf rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
            ]),
            FilterState(correspondent: .anyOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
                .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19)),
            ]),
            FilterState(correspondent: .anyOf(ids: [8, 19])))

        // New noneOf rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
            ]),
            FilterState(correspondent: .noneOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
                .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 19)),
            ]),
            FilterState(correspondent: .noneOf(ids: [8, 19])))
    }

    func testRuleToFilterStateDocumentType() {
        // Old single rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: 8)),
            ]),
            FilterState(documentType: .anyOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: nil)),
            ]),
            FilterState(documentType: .notAssigned))

        // New anyOf rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            ]),
            FilterState(documentType: .anyOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
                .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19)),
            ]),
            FilterState(documentType: .anyOf(ids: [8, 19])))

        // New noneOf rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            ]),
            FilterState(documentType: .noneOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
                .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 19)),
            ]),
            FilterState(documentType: .noneOf(ids: [8, 19])))
    }

    func testRuleToFilterStateRemaining() {
        // Unsupported rules go to "remaining":
        let addedAfter = FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
        XCTAssertEqual(
            FilterState(rules: [addedAfter]).remaining,
            [addedAfter])
    }

    func testRuleToFilterStateTags() {
        let tagAll = [FilterRule]([
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
        ])

        // Single tag all rule
        XCTAssertEqual(
            FilterState(rules: Array(tagAll.prefix(1))),
            FilterState(tags: .allOf(include: [66], exclude: [])))

        XCTAssertEqual(
            FilterState(rules: Array(tagAll.prefix(2))),
            FilterState(tags: .allOf(include: [66, 71], exclude: [])))

        XCTAssertEqual(
            FilterState(rules: tagAll),
            FilterState(tags: .allOf(include: [66, 71], exclude: [75])))

        XCTAssertEqual(
            FilterState(rules: Array(tagAll.suffix(1))),
            FilterState(tags: .allOf(include: [], exclude: [75])))

        XCTAssertEqual(
            FilterState(rules: Array(tagAll.reversed())),
            FilterState(tags: .allOf(include: [71, 66], exclude: [75])))

        let tagAny = [FilterRule]([
            .init(ruleType: .hasTagsAny, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAny, value: .tag(id: 71)),
        ])

        XCTAssertEqual(
            FilterState(rules: Array(tagAny.prefix(1))),
            FilterState(tags: .anyOf(ids: [66])))

        XCTAssertEqual(
            FilterState(rules: tagAny),
            FilterState(tags: .anyOf(ids: [66, 71])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasAnyTag, value: .boolean(value: false)),
            ]),
            FilterState(tags: .notAssigned))

        // @TODO: Test error states
    }

    func testRuleToFilterStateOwner() {
        // @TODO: Implement owner rules!
    }

    func testRuleToFilterStateStoragePath() {
        // Old single rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .storagePath, value: .storagePath(id: 8)),
            ]),
            FilterState(storagePath: .anyOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .storagePath, value: .storagePath(id: nil)),
            ]),
            FilterState(storagePath: .notAssigned))

        // New anyOf rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            ]),
            FilterState(storagePath: .anyOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
                .init(ruleType: .hasStoragePathAny, value: .storagePath(id: 19)),
            ]),
            FilterState(storagePath: .anyOf(ids: [8, 19])))

        // New noneOf rule
        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            ]),
            FilterState(storagePath: .noneOf(ids: [8])))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
                .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 19)),
            ]),
            FilterState(storagePath: .noneOf(ids: [8, 19])))
    }

    // - MARK: FilterState to FilterRule

    func testFilterStateToRuleTextSearch() {
        for mode in [FilterState.SearchMode](
            [.title, .content, .titleContent])
        {
            let state = FilterState(searchText: "hallo", searchMode: mode)

            XCTAssertEqual(state.rules, [
                FilterRule(ruleType: mode.ruleType, value: .string(value: "hallo")),
            ])
        }
    }

    func testFilterStateToRuleEmpty() {
        XCTAssertEqual([], FilterState().rules)
    }

    func testFilterStateToRuleCorrespondent() {
        // Old single rule
        XCTAssertEqual(
            [FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))],
            FilterState(correspondent: .notAssigned).rules)

        // New anyOf rule
        XCTAssertEqual(
            [FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8))],
            FilterState(correspondent: .anyOf(ids: [8])).rules)

        XCTAssertEqual(
            [
                FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)),
                FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 99)),
            ],
            FilterState(correspondent: .anyOf(ids: [8, 99])).rules)

        // New noneOf rule
        XCTAssertEqual(
            [FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8))],
            FilterState(correspondent: .noneOf(ids: [8])).rules)

        XCTAssertEqual(
            [
                FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)),
                FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 99)),
            ],
            FilterState(correspondent: .noneOf(ids: [8, 99])).rules)
    }

    func testFilterStateToRuleDocumentType() {
        // Old single rule
        XCTAssertEqual(
            [FilterRule(ruleType: .documentType, value: .documentType(id: nil))],
            FilterState(documentType: .notAssigned).rules)

        // New anyOf rule
        XCTAssertEqual(
            [FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8))],
            FilterState(documentType: .anyOf(ids: [8])).rules)

        XCTAssertEqual([
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)),
            FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 99)),
        ], FilterState(documentType: .anyOf(ids: [8, 99])).rules)

        // New noneOf rule
        XCTAssertEqual([
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
        ], FilterState(documentType: .noneOf(ids: [8])).rules)

        XCTAssertEqual([
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)),
            FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 99)),
        ], FilterState(documentType: .noneOf(ids: [8, 99])).rules)
    }

    func testFilterStatetoRuleRemaining() {
        // Unsupported rules go to "remaining" and are preserved
        let addedAfter = FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
        XCTAssertEqual(
            FilterState(rules: [addedAfter]).rules,
            [addedAfter])
    }

    func testFilterStateToRuleTags() {
        let tagAll = [FilterRule]([
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
        ])

        XCTAssertEqual(
            tagAll,
            FilterState(tags: .allOf(include: [66, 71], exclude: [75])).rules)

        let tagAny = [FilterRule]([
            .init(ruleType: .hasTagsAny, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAny, value: .tag(id: 71)),
        ])

        XCTAssertEqual(
            tagAny,
            FilterState(tags: .anyOf(ids: [66, 71])).rules)

        XCTAssertEqual(
            [FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false))],
            FilterState(tags: .notAssigned).rules)

        // @TODO: Test error states (do we expect any this direction?)
    }

    func testFilterStateToRuleOwner() {
        // @TODO: Implement owner rules
    }

    func testFilterStateToRuleStoragePath() {
        // Old single rule
        XCTAssertEqual(
            [FilterRule(ruleType: .storagePath, value: .storagePath(id: nil))],
            FilterState(storagePath: .notAssigned).rules)

        // New anyOf rule
        XCTAssertEqual(
            [FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8))],
            FilterState(storagePath: .anyOf(ids: [8])).rules)

        XCTAssertEqual([
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)),
            FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 99)),
        ], FilterState(storagePath: .anyOf(ids: [8, 99])).rules)

        // New noneOf rule
        XCTAssertEqual([
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
        ], FilterState(storagePath: .noneOf(ids: [8])).rules)

        XCTAssertEqual([
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)),
            FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 99)),
        ], FilterState(storagePath: .noneOf(ids: [8, 99])).rules)
    }

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

        XCTAssertEqual(state.tags, .allOf(include: [66, 71], exclude: [75]))

        XCTAssertEqual(state.searchMode, .title)
        XCTAssertEqual(state.searchText, "shantel")
        XCTAssertEqual(state.correspondent, .notAssigned)
        XCTAssertEqual(state.remaining, input.suffix(1))

        XCTAssertEqual(
            state.rules.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue }),
            input.sorted(by: { $0.ruleType.rawValue < $1.ruleType.rawValue }))
    }

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
}
