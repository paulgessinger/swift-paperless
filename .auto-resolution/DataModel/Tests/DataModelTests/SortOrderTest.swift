//
//  SortOrderTest.swift
//  DataModel
//
//  Created by AI Assistant on 03.01.25.
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct SortOrderTest {
  @Test("Tests decoding of boolean values to SortOrder")
  func testDecoding() throws {
    let ascendingJson = "false".data(using: .utf8)!
    let descendingJson = "true".data(using: .utf8)!

    let decodedAscending = try JSONDecoder().decode(DataModel.SortOrder.self, from: ascendingJson)
    let decodedDescending = try JSONDecoder().decode(DataModel.SortOrder.self, from: descendingJson)

    #expect(decodedAscending == .ascending)
    #expect(decodedDescending == .descending)
  }

  @Test("Tests encoding of SortOrder to boolean values")
  func testEncoding() throws {
    let ascending = SortOrder.ascending
    let descending = SortOrder.descending

    let encodedAscending = try JSONEncoder().encode(ascending)
    let encodedDescending = try JSONEncoder().encode(descending)

    let decodedAscending = try JSONDecoder().decode(Bool.self, from: encodedAscending)
    let decodedDescending = try JSONDecoder().decode(Bool.self, from: encodedDescending)

    #expect(decodedAscending == false)
    #expect(decodedDescending == true)
  }

  @Test("Tests reverse property")
  func testReverse() throws {
    #expect(SortOrder.ascending.reverse == false)
    #expect(SortOrder.descending.reverse == true)
  }

  @Test("Tests boolean initialization")
  func testBoolInit() throws {
    #expect(SortOrder(false) == .ascending)
    #expect(SortOrder(true) == .descending)
  }

  @Test("Tests encoding and decoding roundtrip")
  func testRoundtrip() throws {
    let orders: [DataModel.SortOrder] = [.ascending, .descending]

    for order in orders {
      let encoded = try JSONEncoder().encode(order)
      let decoded = try JSONDecoder().decode(DataModel.SortOrder.self, from: encoded)
      #expect(order == decoded)
    }
  }
}
