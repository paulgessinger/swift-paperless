//
//  AppConfigurationModelTest.swift
//  DataModel
//
//  Created by Claude on 09.07.25.
//

import Common
@testable import DataModel
import Foundation
import Testing

private let decoder = makeDecoder(tz: .current)

@Suite
struct AppConfigurationModelTest {
    @Test func testFullConfigurationDecoding() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_full.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that the relevant properties are decoded correctly
        #expect(config.id == 1)
        #expect(config.barcodeAsnPrefix == "ASN")
    }

    @Test func testMinimalConfigurationDecoding() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_minimal.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that only ID is provided and other fields are nil
        #expect(config.id == 2)
        #expect(config.barcodeAsnPrefix == nil)
    }

    @Test func testPartialConfigurationDecoding() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_partial.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that the partial configuration is handled correctly
        #expect(config.id == 3)

        #expect(config.barcodeAsnPrefix == nil) // This field is missing in the partial config
    }

    @Test func testNullValueHandling() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_null_values.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that null values are handled correctly
        #expect(config.id == 4)
        #expect(config.barcodeAsnPrefix == nil) // This field is not present in null values test
    }

    @Test func testSingleConfigurationDecoding() throws {
        // Test decoding a single configuration object (not in array)
        let jsonString = """
        {
            "id": 5,
            "app_title": "Single Config",
            "barcodes_enabled": true,
            "language": "fr"
        }
        """
        let data = jsonString.data(using: .utf8)!
        let config = try decoder.decode(AppConfiguration.self, from: data)

        #expect(config.id == 5)
        #expect(config.barcodeAsnPrefix == nil) // missing field is nil
    }

    @Test func testMissingIdFieldFails() throws {
        let jsonString = """
        {
            "app_title": "No ID Config"
        }
        """
        let data = jsonString.data(using: .utf8)!

        // This should throw because id is required
        #expect(throws: (any Error).self) {
            try decoder.decode(AppConfiguration.self, from: data)
        }
    }

    @Test func testEmptyArrayDecoding() throws {
        let jsonString = "[]"
        let data = jsonString.data(using: .utf8)!
        let configs = try decoder.decode([AppConfiguration].self, from: data)

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
        let config = try decoder.decode(AppConfiguration.self, from: data)

        #expect(config.id == 6)
        #expect(config.barcodeAsnPrefix == nil) // This field is not present in large numbers test
    }
}
