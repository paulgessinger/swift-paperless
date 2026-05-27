//
//  ApiServerConfigurationTest.swift
//  Networking
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

private let decoder = makeDecoder(tz: .current)

@Suite
struct ApiServerConfigurationTest {
  @Test func testFullConfigurationDecoding() throws {
    let data = try #require(testData("Data/AppConfiguration/app_config_full.json"))
    let configs = try decoder.decode([ApiServerConfiguration].self, from: data).map(\.domain)

    #expect(configs.count == 1)
    let config = configs[0]
    #expect(config.id == 1)
    #expect(config.barcodeAsnPrefix == "ASN")
  }

  @Test func testMinimalConfigurationDecoding() throws {
    let data = try #require(testData("Data/AppConfiguration/app_config_minimal.json"))
    let configs = try decoder.decode([ApiServerConfiguration].self, from: data).map(\.domain)

    #expect(configs.count == 1)
    let config = configs[0]
    #expect(config.id == 2)
    #expect(config.barcodeAsnPrefix == nil)
  }

  @Test func testPartialConfigurationDecoding() throws {
    let data = try #require(testData("Data/AppConfiguration/app_config_partial.json"))
    let configs = try decoder.decode([ApiServerConfiguration].self, from: data).map(\.domain)

    #expect(configs.count == 1)
    let config = configs[0]
    #expect(config.id == 3)
    #expect(config.barcodeAsnPrefix == nil)
  }

  @Test func testNullValueHandling() throws {
    let data = try #require(testData("Data/AppConfiguration/app_config_null_values.json"))
    let configs = try decoder.decode([ApiServerConfiguration].self, from: data).map(\.domain)

    #expect(configs.count == 1)
    let config = configs[0]
    #expect(config.id == 4)
    #expect(config.barcodeAsnPrefix == nil)
  }

  @Test func testSingleConfigurationDecoding() throws {
    let jsonString = """
      {
          "id": 5,
          "app_title": "Single Config",
          "barcodes_enabled": true,
          "language": "fr"
      }
      """
    let data = jsonString.data(using: .utf8)!
    let config = try decoder.decode(ApiServerConfiguration.self, from: data).domain

    #expect(config.id == 5)
    #expect(config.barcodeAsnPrefix == nil)
  }

  @Test func testMissingIdFieldFails() throws {
    let jsonString = """
      {
          "app_title": "No ID Config"
      }
      """
    let data = jsonString.data(using: .utf8)!

    #expect(throws: (any Error).self) {
      try decoder.decode(ApiServerConfiguration.self, from: data)
    }
  }

  @Test func testEmptyArrayDecoding() throws {
    let jsonString = "[]"
    let data = jsonString.data(using: .utf8)!
    let configs = try decoder.decode([ApiServerConfiguration].self, from: data).map(\.domain)

    #expect(configs.isEmpty)
  }

  @Test func testLargeNumberHandling() throws {
    let jsonString = """
      {
          "id": 6,
          "pages": 9223372036854775807,
          "image_dpi": 4294967295,
          "max_image_pixels": 18446744073709551615
      }
      """
    let data = jsonString.data(using: .utf8)!
    let config = try decoder.decode(ApiServerConfiguration.self, from: data).domain

    #expect(config.id == 6)
    #expect(config.barcodeAsnPrefix == nil)
  }
}
