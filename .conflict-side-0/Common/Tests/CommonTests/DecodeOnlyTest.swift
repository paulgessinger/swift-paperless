//
//  DecodeOnlyTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 24.07.2024.
//

import Foundation
import Testing

@testable import Common

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

@Suite
struct DecodeOnlyTest {
  @Test
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
    #expect(result.normal == 5)
    #expect(result.decodeOnly == 72)
    #expect(result.decodeOnlyStruct.value == 66)
  }

  @Test
  func testDecodeFailsIfNotPresent() throws {
    let input1 = """
      {
          "normal": 5,
          "decodeOnlyStruct": {
              "value": 66
          }
      }
      """.data(using: .utf8)!

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Element.self, from: input1)
    }

    let input2 = """
      {
          "normal": 5,
          "decodeOnly": 72,
          "decodeOnlyStruct": {
          }
      }
      """.data(using: .utf8)!

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Element.self, from: input2)
    }
  }

  @Test
  func testDecodeOptional() throws {
    do {
      let input = """
        {
            "normal": 5,
            "optDecodeOnly": 6
        }
        """.data(using: .utf8)!

      let result = try JSONDecoder().decode(ElementOpt.self, from: input)
      #expect(result.normal == 5)

      let optDecodeOnly = try #require(result.optDecodeOnly)
      #expect(optDecodeOnly == 6)
    }

    do {
      let input = """
        {
            "normal": 5,
        }
        """.data(using: .utf8)!

      let result = try JSONDecoder().decode(ElementOpt.self, from: input)
      #expect(result.normal == 5)
      #expect(result.optDecodeOnly == nil)
    }
  }

  @Test
  func testEncode() throws {
    let value = Element(
      normal: 3,
      decodeOnly: 99,
      decodeOnlyStruct: .init(value: 9)
    )

    let data = try JSONEncoder().encode(value)
    let str = String(data: data, encoding: .utf8)!

    #expect(str == "{\"normal\":3}")
  }
}
