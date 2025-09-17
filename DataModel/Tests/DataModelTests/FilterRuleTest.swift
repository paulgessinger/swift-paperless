//
//  FilterRuleTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 21.12.24.
//

import Common
import Foundation
import Testing

@testable import DataModel

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

    let result = try JSONDecoder().decode(
      ListResponse<SavedView>.self, from: input.data(using: .utf8)!)
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
      FilterRule(ruleType: .title, value: .string(value: "shantel"))!,
      FilterRule(ruleType: .hasTagsAll, value: .tag(id: 66))!,
      FilterRule(ruleType: .hasTagsAll, value: .tag(id: 71))!,
      FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: 75))!,
      FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))!,
    ]

    try #require(result.count == expected.count + 1)

    for i in 0..<expected.count {
      print(i, result.count, expected.count)
      #expect(result[i] == expected[i])
    }

    let last = try #require(result.last)

    #expect(last.ruleType == .addedAfter)

    switch last.value {
    case .date(let date):
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
      FilterRule(ruleType: .title, value: .string(value: "shantel"))!,
      FilterRule(ruleType: .hasTagsAll, value: .tag(id: 66))!,
      FilterRule(ruleType: .hasTagsAll, value: .tag(id: 71))!,
      FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: 75))!,
      FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))!,
      FilterRule(
        ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1, tz: .gmt))
      )!,
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
      FilterRule(ruleType: .title, value: .string(value: "shantel"))!,
      FilterRule(ruleType: .hasTagsAll, value: .tag(id: 66))!,
      FilterRule(ruleType: .hasTagsAll, value: .tag(id: 71))!,
      FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: 75))!,
      FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))!,
      FilterRule(
        ruleType: .addedAfter, value: .date(value: datetime(year: 2023, month: 1, day: 1, tz: .gmt))
      )!,
      FilterRule(ruleType: .storagePath, value: .storagePath(id: 8))!,
      FilterRule(ruleType: .storagePath, value: .storagePath(id: nil))!,
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
      try [URLQueryItem(name: "is_tagged", value: "0")]
        == FilterRule.queryItems(for: [
          #require(FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false)))
        ])
    )
  }

  @Test
  func testFilterOwner() throws {
    let input1 = try #require(FilterRule(ruleType: .owner, value: .owner(id: 8)))
    let items = FilterRule.queryItems(for: [input1])
    #expect(items == [URLQueryItem(name: "owner__id", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .ownerAny, value: .owner(id: 8)))
      ]) == [URLQueryItem(name: "owner__id__in", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .ownerAny, value: .owner(id: 8))),
        #require(FilterRule(ruleType: .ownerAny, value: .owner(id: 19))),
      ]) == [URLQueryItem(name: "owner__id__in", value: "19,8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true)))
      ]) == [URLQueryItem(name: "owner__isnull", value: "1")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .owner(id: 25)))
      ]) == [URLQueryItem(name: "owner__id__none", value: "25")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .owner(id: 25))),
        #require(FilterRule(ruleType: .ownerDoesNotInclude, value: .owner(id: 99))),
      ]) == [URLQueryItem(name: "owner__id__none", value: "25,99")])
  }

  @Test
  func testFilterDocumentType() throws {
    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .documentType, value: .documentType(id: 8)))
      ]) == [URLQueryItem(name: "document_type__id", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8)))
      ]) == [URLQueryItem(name: "document_type__id__in", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 8))),
        #require(FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: 19))),
      ]) == [URLQueryItem(name: "document_type__id__in", value: "19,8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8)))
      ]) == [URLQueryItem(name: "document_type__id__none", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: 87))),
      ]) == [URLQueryItem(name: "document_type__id__none", value: "8,87")])
  }

  @Test
  func testCorrespondent() throws {
    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .correspondent, value: .correspondent(id: 8)))
      ]) == [URLQueryItem(name: "correspondent__id", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8)))
      ]) == [URLQueryItem(name: "correspondent__id__in", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 8))),
        #require(FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: 19))),
      ]) == [URLQueryItem(name: "correspondent__id__in", value: "19,8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8)))
      ]) == [URLQueryItem(name: "correspondent__id__none", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: 87))),
      ]) == [URLQueryItem(name: "correspondent__id__none", value: "8,87")])
  }

  @Test
  func testStoragePath() throws {
    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .storagePath, value: .storagePath(id: 8)))
      ]) == [URLQueryItem(name: "storage_path__id", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8)))
      ]) == [URLQueryItem(name: "storage_path__id__in", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 8))),
        #require(FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: 19))),
      ]) == [URLQueryItem(name: "storage_path__id__in", value: "19,8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8)))
      ]) == [URLQueryItem(name: "storage_path__id__none", value: "8")])

    #expect(
      try FilterRule.queryItems(for: [
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 8))),
        #require(FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: 87))),
      ]) == [URLQueryItem(name: "storage_path__id__none", value: "8,87")])
  }

  @Test
  func testDecodingComplexCustomFieldQuery() throws {
    let query = """
      ["OR",[[11,"isnull","true"],[11,"exists","false"],["AND",[[10,"exists","true"],["OR",[[8,"exact","x"],[5,"gt","6"],[10,"in",["aaa","bbb"]],[9,"contains",[3]]]]]],[3,"gte","2024-12-12"]]]
      """.trimmingCharacters(in: .whitespaces)

    let direct = try #require(CustomFieldQuery(rawValue: query))

    struct Data: Encodable {
      var rule_type: Int
      var value: String
    }

    let data = try JSONEncoder().encode(Data(rule_type: 42, value: query))

    let result = try JSONDecoder().decode(FilterRule.self, from: data)

    #expect(result.ruleType == .customFieldsQuery)
    #expect(result.value == .customFieldQuery(direct))
  }

  @Test
  func testInitializerReturnsNilForTypeMismatch() throws {
    // Test cases where ruleType.dataType() doesn't match the FilterRuleValue case
    #expect(FilterRule(ruleType: .title, value: .number(value: 42)) == nil)
    #expect(FilterRule(ruleType: .hasTagsAll, value: .string(value: "invalid")) == nil)
    #expect(FilterRule(ruleType: .addedAfter, value: .boolean(value: true)) == nil)
    #expect(FilterRule(ruleType: .correspondent, value: .date(value: Date())) == nil)
    #expect(FilterRule(ruleType: .documentType, value: .tag(id: 1)) == nil)
    #expect(FilterRule(ruleType: .storagePath, value: .number(value: 123)) == nil)
    #expect(FilterRule(ruleType: .owner, value: .string(value: "owner")) == nil)

    // Test custom field query specific case
    #expect(
      FilterRule(ruleType: .customFieldsQuery, value: .string(value: "not a custom field query"))
        == nil)
  }

  @Test
  func testInitializerReturnsValidForTypeMatch() throws {
    // Test cases where ruleType.dataType() matches the FilterRuleValue case
    let titleRule = try #require(FilterRule(ruleType: .title, value: .string(value: "test")))
    #expect(titleRule.ruleType == .title)
    #expect(titleRule.value == .string(value: "test"))

    let tagRule = try #require(FilterRule(ruleType: .hasTagsAll, value: .tag(id: 1)))
    #expect(tagRule.ruleType == .hasTagsAll)
    #expect(tagRule.value == .tag(id: 1))

    let booleanRule = try #require(FilterRule(ruleType: .hasAnyTag, value: .boolean(value: true)))
    #expect(booleanRule.ruleType == .hasAnyTag)
    #expect(booleanRule.value == .boolean(value: true))

    let date = Date()
    let dateRule = try #require(FilterRule(ruleType: .addedAfter, value: .date(value: date)))
    #expect(dateRule.ruleType == .addedAfter)
    #expect(dateRule.value == .date(value: date))

    let correspondentRule = try #require(
      FilterRule(ruleType: .correspondent, value: .correspondent(id: 1)))
    #expect(correspondentRule.ruleType == .correspondent)
    #expect(correspondentRule.value == .correspondent(id: 1))

    let documentTypeRule = try #require(
      FilterRule(ruleType: .documentType, value: .documentType(id: 1)))
    #expect(documentTypeRule.ruleType == .documentType)
    #expect(documentTypeRule.value == .documentType(id: 1))

    let storagePathRule = try #require(
      FilterRule(ruleType: .storagePath, value: .storagePath(id: 1)))
    #expect(storagePathRule.ruleType == .storagePath)
    #expect(storagePathRule.value == .storagePath(id: 1))

    let ownerRule = try #require(FilterRule(ruleType: .owner, value: .owner(id: 1)))
    #expect(ownerRule.ruleType == .owner)
    #expect(ownerRule.value == .owner(id: 1))

    // Test custom field query specific case
    let query = CustomFieldQuery.expr(8, .exists, .string("true"))
    let rule1 = try #require(
      FilterRule(ruleType: .customFieldsQuery, value: .customFieldQuery(query)))
    #expect(rule1.ruleType == .customFieldsQuery)
    #expect(rule1.value == .customFieldQuery(query))

    let rule2 = try #require(
      FilterRule(ruleType: .customFieldsQuery, value: .string(value: query.rawValue)))
    #expect(rule2.ruleType == .customFieldsQuery)
    #expect(rule2.value == .customFieldQuery(query))
  }

  @Test
  func testCustomFieldQueryFilterRuleWithComplexQuery() throws {
    let complexQuery = CustomFieldQuery.op(
      .or,
      [
        .expr(11, .isnull, .string("true")),
        .expr(1, .gt, .number(1.2)),
        .op(
          .and,
          [
            .expr(10, .exists, .string("true")),
            .expr(9, .contains, .array([.integer(3)])),
          ]
        ),
      ]
    )

    let filterRule = try #require(
      FilterRule(ruleType: .customFieldsQuery, value: .customFieldQuery(complexQuery)))

    let queryItems = FilterRule.queryItems(for: [filterRule])

    #expect(queryItems.count == 1)
    #expect(queryItems[0].name == "custom_field_query")
    #expect(queryItems[0].value == complexQuery.rawValue)
  }
}
