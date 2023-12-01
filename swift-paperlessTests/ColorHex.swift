//
//  ColorHex.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 26.02.23.
//

@testable import swift_paperless
import XCTest

import SwiftUI

struct TestStruct: Codable {
    var color: HexColor
}

final class ColorHex: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFromHex() throws {
        XCTAssertThrowsError(try Color(hex: "nope"))

        XCTAssertEqual(try Color(hex: "#ffffff"), Color.white)
//        XCTAssertEqual(Color.hex("#fff"), Color.white)
//        XCTAssertEqual(Color.hex("#000"), Color.black)
        XCTAssertEqual(try Color(hex: "#000000"), Color.black)
        XCTAssertEqual(try Color(hex: "#ff0000"), Color(.sRGB, red: 1, green: 0, blue: 0))
        XCTAssertEqual(try Color(hex: "#00ff00"), Color(.sRGB, red: 0, green: 1, blue: 0))
        XCTAssertEqual(try Color(hex: "#0000ff"), Color(.sRGB, red: 0, green: 0, blue: 1))
    }

    func testToHex() throws {
        XCTAssertEqual("#ffffff", Color.white.hexString)
        XCTAssertEqual("#000000", Color.black.hexString)
        XCTAssertEqual("#ff0000", Color(.sRGB, red: 1, green: 0, blue: 0).hexString)
        XCTAssertEqual("#00ff00", Color(.sRGB, red: 0, green: 1, blue: 0).hexString)
        XCTAssertEqual("#0000ff", Color(.sRGB, red: 0, green: 0, blue: 1).hexString)
    }

    let inputs = [
        ("#ffffff", Color.white),
        ("#000000", Color.black),
        ("#ff0000", Color(.sRGB, red: 1, green: 0, blue: 0)),
        ("#00ff00", Color(.sRGB, red: 0, green: 1, blue: 0)),
        ("#0000ff", Color(.sRGB, red: 0, green: 0, blue: 1)),
    ]

    func testFromJson() throws {
        for (s, c) in inputs {
            let input = "{\"color\":\"\(s)\"}".data(using: .utf8)!
            let test = try decoder.decode(TestStruct.self, from: input)
            XCTAssertNotNil(test)
            XCTAssertEqual(test.color.color, c)
        }
    }

    func testToJson() throws {
        let encoder = JSONEncoder()
        for (s, c) in inputs {
            let value = TestStruct(color: c.hex)
            let data = try encoder.encode(value)
            let string = String(data: data, encoding: .utf8)!
            let expected = "{\"color\":\"\(s)\"}"
            XCTAssertEqual(string, expected)
        }
    }
}
