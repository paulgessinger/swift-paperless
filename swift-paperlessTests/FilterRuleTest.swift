//
//  FilterRuleTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 02.04.23.
//

import XCTest

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

        var dateComponents = DateComponents()
        dateComponents.year = 2023
        dateComponents.month = 1
        dateComponents.day = 1
        dateComponents.timeZone = TimeZone(abbreviation: "CEST")
        dateComponents.hour = 0
        dateComponents.minute = 0

        let datetime = Calendar(identifier: .gregorian).date(from: dateComponents)!

        let expected: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime)),
        ]

        XCTAssertEqual(result, expected)
    }

    func testEncoding() throws {
        let input = FilterRule(ruleType: .hasTagsAll, value: .tag(id: 6))

        let data = try String(data: JSONEncoder().encode(input), encoding: .utf8)!

        XCTAssertEqual(data, "{\"rule_type\":6,\"value\":\"6\"}")
    }

    func testEncodingMultiple() throws {
        var dateComponents = DateComponents()
        dateComponents.year = 2023
        dateComponents.month = 1
        dateComponents.day = 1
        dateComponents.timeZone = TimeZone(abbreviation: "CEST")
        dateComponents.hour = 0
        dateComponents.minute = 0

        let datetime = Calendar(identifier: .gregorian).date(from: dateComponents)!

        let input: [FilterRule] = [
            .init(ruleType: .title, value: .string(value: "shantel")),
            .init(ruleType: .hasTagsAll, value: .tag(id: 66)),
            .init(ruleType: .hasTagsAll, value: .tag(id: 71)),
            .init(ruleType: .doesNotHaveTag, value: .tag(id: 75)),
            .init(ruleType: .correspondent, value: .correspondent(id: nil)),
            .init(ruleType: .addedAfter, value: .date(value: datetime)),
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
}
