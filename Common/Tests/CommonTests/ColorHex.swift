//
//  ColorHex.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 26.02.23.
//

@testable import Common
import Foundation
import SwiftUI
import Testing

@Suite struct ColorHexTests {
    private struct TestStruct: Codable {
        var color: HexColor
    }

    @Test
    func testFromHex() throws {
        #expect(Color(hex: "nope") == nil)

        #expect(Color(hex: "#ffffff")! == Color.white)
        #expect(Color(hex: "#000000")! == Color.black)
        #expect(Color(hex: "#ff0000")! == Color(.sRGB, red: 1, green: 0, blue: 0))
        #expect(Color(hex: "#00ff00")! == Color(.sRGB, red: 0, green: 1, blue: 0))
        #expect(Color(hex: "#0000ff")! == Color(.sRGB, red: 0, green: 0, blue: 1))
    }

    @Test
    func testToHex() throws {
        #expect(Color.white.hexString == "#ffffff")
        #expect(Color.black.hexString == "#000000")
        #expect(Color(.sRGB, red: 1, green: 0, blue: 0).hexString == "#ff0000")
        #expect(Color(.sRGB, red: 0, green: 1, blue: 0).hexString == "#00ff00")
        #expect(Color(.sRGB, red: 0, green: 0, blue: 1).hexString == "#0000ff")
    }

    private let inputs = [
        ("#ffffff", Color.white),
        ("#000000", Color.black),
        ("#ff0000", Color(.sRGB, red: 1, green: 0, blue: 0)),
        ("#00ff00", Color(.sRGB, red: 0, green: 1, blue: 0)),
        ("#0000ff", Color(.sRGB, red: 0, green: 0, blue: 1)),
    ]

    @Test
    func testFromJson() throws {
        for (s, c) in inputs {
            let input = "{\"color\":\"\(s)\"}".data(using: .utf8)!
            let test = try #require(try JSONDecoder().decode(TestStruct.self, from: input))
            #expect(test.color.color == c)
        }
    }

    @Test
    func testToJson() throws {
        let encoder = JSONEncoder()
        for (s, c) in inputs {
            let value = TestStruct(color: c.hex)
            let data = try encoder.encode(value)
            let string = String(data: data, encoding: .utf8)!
            let expected = "{\"color\":\"\(s)\"}"
            #expect(string == expected)
        }
    }
}
