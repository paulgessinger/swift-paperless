//
//  FilterRuleTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 21.12.24.
//

import Common
@testable import DataModel
import Foundation
import Testing

struct DecodeHelper: Codable, Equatable {
    let rule_type: Int
    let value: String?
}

@Suite
struct FilterRuleTest {
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

    @Test func testDecodingMultiple() throws {
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

        let result = try makeDecoder(tz: .current).decode([FilterRule].self, from: input)

        let expected: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
        ]

        try #require(result.count == expected.count + 1)

        for i in 0 ..< expected.count {
            print(i, result.count, expected.count)
            #expect(result[i] == expected[i])
        }

        let last = try #require(result.last)

        #expect(last.ruleType == .addedAfter)

        switch last.value {
        case let .date(date):
            #expect(dateApprox(date, datetime(year: 2023, month: 1, day: 1, tz: .gmt)))
        default:
            #expect(Bool(false))
        }

//        #expect(result.last == FilterRule(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1, tz: .current))))
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
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1, tz: .gmt))),
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
            .init(ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1, tz: .gmt))),
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
}
