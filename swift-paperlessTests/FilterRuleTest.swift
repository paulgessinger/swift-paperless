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
    dateComponents.timeZone = TimeZone(abbreviation: "CEST")
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
        ]
        expected.sort(by: sort)

        XCTAssertEqual(items[0], expected[0])
        XCTAssertEqual(items, expected)

        XCTAssertEqual(
            [URLQueryItem(name: "is_tagged", value: "0")],
            FilterRule.queryItems(for: [.init(ruleType: .hasAnyTag, value: .boolean(value: false))]))
    }

    func testSearchModeConversion() {
        XCTAssertEqual(FilterRuleType.title, FilterState.SearchMode.title.ruleType)
        XCTAssertEqual(FilterRuleType.content, FilterState.SearchMode.content.ruleType)
        XCTAssertEqual(FilterRuleType.titleContent, FilterState.SearchMode.titleContent.ruleType)

        XCTAssertEqual(FilterState.SearchMode(ruleType: .title), FilterState.SearchMode.title)
        XCTAssertEqual(FilterState.SearchMode(ruleType: .content), FilterState.SearchMode.content)
        XCTAssertEqual(FilterState.SearchMode(ruleType: .titleContent), FilterState.SearchMode.titleContent)
    }

    func testRuleToFilterState() {
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

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: 8)),
            ]),
            FilterState(correspondent: .only(id: 8)))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            ]),
            FilterState(correspondent: .notAssigned))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: 8)),
            ]),
            FilterState(documentType: .only(id: 8)))

        XCTAssertEqual(
            FilterState(rules: [
                .init(ruleType: .documentType, value: .documentType(id: nil)),
            ]),
            FilterState(documentType: .notAssigned))

        // Unsupported rules go to "remaining":
        let addedAfter = FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
        XCTAssertEqual(
            FilterState(rules: [addedAfter]).remaining,
            [addedAfter])

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

    func testFilterStateToRule() {
        for mode in [FilterState.SearchMode](
            [.title, .content, .titleContent])
        {
            let state = FilterState(searchText: "hallo", searchMode: mode)

            XCTAssertEqual(state.rules, [
                FilterRule(ruleType: mode.ruleType, value: .string(value: "hallo")),
            ])
        }

        XCTAssertEqual([], FilterState().rules)

        XCTAssertEqual(
            [FilterRule(ruleType: .correspondent, value: .correspondent(id: 8))],
            FilterState(correspondent: .only(id: 8)).rules)

        XCTAssertEqual(
            [FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))],
            FilterState(correspondent: .notAssigned).rules)

        XCTAssertEqual(
            [FilterRule(ruleType: .documentType, value: .documentType(id: 8))],
            FilterState(documentType: .only(id: 8)).rules)

        XCTAssertEqual(
            [FilterRule(ruleType: .documentType, value: .documentType(id: nil))],
            FilterState(documentType: .notAssigned).rules)

        // Unsupported rules go to "remaining" and are preserved
        let addedAfter = FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1)))
        XCTAssertEqual(
            FilterState(rules: [addedAfter]).rules,
            [addedAfter])

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

    func testRulesToFilterState() throws {
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
