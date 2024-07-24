//
//  DecodeOnlyTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 24.07.2024.
//

import XCTest

private struct SubElement: Decodable {
    var value: Int
}

private struct Element: Codable {
    var normal: Int

    @DecodeOnly
    var decodeOnly: Int

    @DecodeOnly
    var decodeOnlyStruct: SubElement
}

private struct ElementOpt: Codable {
    var normal: Int

    @DecodeOnly
    var optDecodeOnly: Int?
}

final class DecodeOnlyTest: XCTestCase {
    func testDecode() throws {
        let input = """
        {
            "normal": 5,
            "decodeOnly": 72,
            "decodeOnlyStruct": {
                "value": 66
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(Element.self, from: input)
        XCTAssertEqual(result.normal, 5)
        XCTAssertEqual(result.decodeOnly, 72)
        XCTAssertEqual(result.decodeOnlyStruct.value, 66)
    }

    func testDecodeFailsIfNotPresent() throws {
        let input1 = """
        {
            "normal": 5,
            "decodeOnlyStruct": {
                "value": 66
            }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Element.self, from: input1))

        let input2 = """
        {
            "normal": 5,
            "decodeOnly": 72,
            "decodeOnlyStruct": {
            }
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Element.self, from: input2))
    }

    func testDecodeOptional() throws {
        do {
            let input = """
            {
                "normal": 5,
                "optDecodeOnly": 6
            }
            """.data(using: .utf8)!

            let result = try JSONDecoder().decode(ElementOpt.self, from: input)
            XCTAssertEqual(result.normal, 5)
            guard let optDecodeOnly = result.optDecodeOnly else {
                XCTFail()
                return
            }
            XCTAssertEqual(optDecodeOnly, 6)
        }

        do {
            let input = """
            {
                "normal": 5,
            }
            """.data(using: .utf8)!

            let result = try JSONDecoder().decode(ElementOpt.self, from: input)
            XCTAssertEqual(result.normal, 5)
            XCTAssertEqual(result.optDecodeOnly, nil)
        }
    }

    func testEncode() throws {
        let value = Element(
            normal: 3,
            decodeOnly: 99,
            decodeOnlyStruct: .init(value: 9)
        )

        let data = try JSONEncoder().encode(value)
        let str = String(data: data, encoding: .utf8)!

        XCTAssertEqual(str, "{\"normal\":3}")
    }
}
