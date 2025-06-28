//
//  CustomFieldQueryTests.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
import Foundation
import Testing

@testable import DataModel

@Suite
struct CustomFieldQueryTests {
    @Test("Tests decoding of custom field query")
    func testDecodingBasicOr() throws {
        let json = """
        ["AND",[[8,"exists","true"],[7,"isnull","true"]]]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CustomFieldQuery.self, from: json)

        #expect(
            decoded
                == .op(
                    .and,
                    [
                        .expr(8, .exists, .string("true")),
                        .expr(7, .isnull, .string("true")),
                    ]
                ))
    }

    @Test("Test decoding with logical sub-expressions")
    func testDecodingLogicalSubExpressions() throws {
        let json = """
        ["OR", [
                [11,"isnull","true"],
                [1,"gt",1.2],
                ["AND", [
                    [10,"exists","true"],
                    ["OR", [
                        [8,"exact","x"],
                        [5,"gt","6"],
                        [10,"exact","9whg6VME2kWnDy9w"],
                        [11,"in",["aaa","bbb"]],
                        [9,"contains",[3]]
                    ]]
                ]],
                [3,"gte","2024-12-12"]
            ]
        ]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CustomFieldQuery.self, from: json)

        #expect(
            decoded
                == .op(
                    .or,
                    [
                        .expr(11, .isnull, .string("true")),
                        .expr(1, .gt, .number(1.2)),
                        .op(
                            .and,
                            [
                                .expr(10, .exists, .string("true")),
                                .op(
                                    .or,
                                    [
                                        .expr(8, .exact, .string("x")),
                                        .expr(5, .gt, .string("6")),
                                        .expr(10, .exact, .string("9whg6VME2kWnDy9w")),
                                        .expr(
                                            11, .in,
                                            .array([
                                                .string("aaa"),
                                                .string("bbb"),
                                            ])
                                        ),
                                        .expr(9, .contains, .array([.integer(3)])),
                                    ]
                                ),
                            ]
                        ),
                        .expr(3, .gte, .string("2024-12-12")),
                    ]
                ))
    }

    @Test("Test decoding individual field expressions")
    func testDecodingIndividualExpressions() throws {
        // Test exists operator
        let existsJson = """
        [8,"exists","true"]
        """.data(using: .utf8)!
        let existsDecoded = try JSONDecoder().decode(CustomFieldQuery.self, from: existsJson)
        #expect(existsDecoded == .expr(8, .exists, .string("true")))

        // Test isnull operator
        let isnullJson = """
        [7,"isnull","true"]
        """.data(using: .utf8)!
        let isnullDecoded = try JSONDecoder().decode(CustomFieldQuery.self, from: isnullJson)
        #expect(isnullDecoded == .expr(7, .isnull, .string("true")))

        // Test exact operator
        let exactJson = """
        [8,"exact","x"]
        """.data(using: .utf8)!
        let exactDecoded = try JSONDecoder().decode(CustomFieldQuery.self, from: exactJson)
        #expect(exactDecoded == .expr(8, .exact, .string("x")))

        // Test gt operator with number
        let gtJson = """
        [1,"gt",1.2]
        """.data(using: .utf8)!
        let gtDecoded = try JSONDecoder().decode(CustomFieldQuery.self, from: gtJson)
        #expect(gtDecoded == .expr(1, .gt, .number(1.2)))

        // Test gte operator with date
        let gteJson = """
        [3,"gte","2024-12-12"]
        """.data(using: .utf8)!
        let gteDecoded = try JSONDecoder().decode(CustomFieldQuery.self, from: gteJson)
        #expect(gteDecoded == .expr(3, .gte, .string("2024-12-12")))

        // Test contains operator with array
        let containsJson = """
        [9,"contains",[3]]
        """.data(using: .utf8)!
        let containsDecoded = try JSONDecoder().decode(CustomFieldQuery.self, from: containsJson)
        #expect(containsDecoded == .expr(9, .contains, .array([.integer(3)])))
    }

    @Test("Test encoding individual field expressions")
    func testEncodingIndividualExpressions() throws {
        let existsQuery = CustomFieldQuery.expr(8, .exists, .string("true"))
        let existsData = try JSONEncoder().encode(existsQuery)
        let existsJson = String(data: existsData, encoding: .utf8)!
        #expect(existsJson == "[8,\"exists\",\"true\"]")

        let gtQuery = CustomFieldQuery.expr(1, .gt, .number(1.2))
        let gtData = try JSONEncoder().encode(gtQuery)
        let gtJson = String(data: gtData, encoding: .utf8)!
        #expect(gtJson == "[1,\"gt\",1.2]")

        let containsQuery = CustomFieldQuery.expr(9, .contains, .array([.integer(3)]))
        let containsData = try JSONEncoder().encode(containsQuery)
        let containsJson = String(data: containsData, encoding: .utf8)!
        #expect(containsJson == "[9,\"contains\",[3]]")
    }

    @Test("Test encoding logical operations")
    func testEncodingLogicalOperations() throws {
        let andQuery = CustomFieldQuery.op(
            .and,
            [
                .expr(8, .exists, .string("true")),
                .expr(7, .isnull, .string("true")),
            ]
        )
        let andData = try JSONEncoder().encode(andQuery)
        let andJson = String(data: andData, encoding: .utf8)!
        #expect(andJson == "[\"AND\",[[8,\"exists\",\"true\"],[7,\"isnull\",\"true\"]]]")
    }

    @Test("Test round-trip encoding/decoding")
    func testRoundTripEncodingDecoding() throws {
        let originalQuery = CustomFieldQuery.op(
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

        let encoded = try JSONEncoder().encode(originalQuery)
        let decoded = try JSONDecoder().decode(CustomFieldQuery.self, from: encoded)
        #expect(decoded == originalQuery)
    }

    @Test("Test RawRepresentable rawValue property")
    func testRawValue() throws {
        let query = CustomFieldQuery.op(
            .and,
            [
                .expr(8, .exists, .string("true")),
                .expr(7, .isnull, .string("true")),
            ]
        )

        let rawValue = query.rawValue
        #expect(rawValue == """
        ["AND",[[8,"exists","true"],[7,"isnull","true"]]]
        """)
    }

    @Test("Test RawRepresentable init from rawValue")
    func testInitFromRawValue() throws {
        let originalQuery = CustomFieldQuery.op(
            .or,
            [
                .expr(11, .isnull, .string("true")),
                .expr(1, .gt, .number(1.2)),
            ]
        )

        let rawValue = originalQuery.rawValue
        let reconstructedQuery = try #require(CustomFieldQuery(rawValue: rawValue))

        #expect(reconstructedQuery == originalQuery)
    }
}
