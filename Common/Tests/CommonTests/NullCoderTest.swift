//
//  NullCoderTest.swift
//  Common
//

import Foundation
import MetaCodable
import Testing

@testable import Common

@Codable
@MemberInit
private struct NullCodedOptional {
  @CodedBy(NullCoder<UInt>())
  var parent: UInt?
}

@Codable
@MemberInit
private struct PlainOptional {
  var parent: UInt?
}

@Suite("NullCoder Tests")
struct NullCoderTestSuite {
  @Test("Encodes explicit JSON null when value is nil")
  func testEncodesExplicitNullWhenNil() throws {
    let value = NullCodedOptional(parent: nil)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    let dict = try #require(json as? [String: Any])

    #expect(dict.keys.contains("parent"))
    #expect(dict["parent"] is NSNull)
  }

  @Test("Encodes non-nil value")
  func testEncodesValueWhenPresent() throws {
    let value = NullCodedOptional(parent: 42)
    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    let dict = try #require(json as? [String: Any])

    #expect((dict["parent"] as? NSNumber)?.uintValue == 42)
  }

  @Test("Decodes JSON null as nil")
  func testDecodesNullAsNil() throws {
    let data = try #require(#"{"parent":null}"#.data(using: .utf8))
    let decoded = try JSONDecoder().decode(NullCodedOptional.self, from: data)
    #expect(decoded.parent == nil)
  }

  @Test("Decodes non-null value")
  func testDecodesValueWhenPresent() throws {
    let data = try #require(#"{"parent":7}"#.data(using: .utf8))
    let decoded = try JSONDecoder().decode(NullCodedOptional.self, from: data)
    #expect(decoded.parent == 7)
  }

  @Test("Plain optional omits key when nil")
  func testPlainOptionalOmitsKeyWhenNil() throws {
    let value = PlainOptional(parent: nil)
    let json = try #require(String(data: JSONEncoder().encode(value), encoding: .utf8))
    #expect(json == "{}")
  }
}
