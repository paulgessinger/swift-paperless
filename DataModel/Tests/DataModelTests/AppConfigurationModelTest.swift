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

        // Test all properties are decoded correctly
        #expect(config.id == 1)
        #expect(config.userArgs == "--some-arg=value")
        #expect(config.barcodeTagMapping == "PAPERLESS_ASN:{asn}")
        #expect(config.outputType == "pdf")
        #expect(config.pages == 100)
        #expect(config.language == "en")
        #expect(config.mode == "consume")
        #expect(config.skipArchiveFile == "never")
        #expect(config.imageDpi == 300)
        #expect(config.unpaperClean == "clean")
        #expect(config.deskew == true)
        #expect(config.rotatePages == true)
        #expect(config.rotatePagesThreshold == 5.5)
        #expect(config.maxImagePixels == 50_000_000)
        #expect(config.colorConversionStrategy == "LeaveColorUnchanged")
        #expect(config.appTitle == "Paperless-ngx")
        #expect(config.appLogo == "png")
        #expect(config.barcodesEnabled == true)
        #expect(config.barcodeEnableTiffSupport == true)
        #expect(config.barcodeString == "PAPERLESS")
        #expect(config.barcodeRetainSplitPages == true)
        #expect(config.barcodeEnableAsn == true)
        #expect(config.barcodeAsnPrefix == "ASN")
        #expect(config.barcodeUpscale == 2.0)
        #expect(config.barcodeDpi == 600)
        #expect(config.barcodeMaxPages == 50)
        #expect(config.barcodeEnableTag == true)
    }

    @Test func testMinimalConfigurationDecoding() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_minimal.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that only ID is provided and all other fields are nil
        #expect(config.id == 2)
        #expect(config.userArgs == nil)
        #expect(config.barcodeTagMapping == nil)
        #expect(config.outputType == nil)
        #expect(config.pages == nil)
        #expect(config.language == nil)
        #expect(config.mode == nil)
        #expect(config.skipArchiveFile == nil)
        #expect(config.imageDpi == nil)
        #expect(config.unpaperClean == nil)
        #expect(config.deskew == nil)
        #expect(config.rotatePages == nil)
        #expect(config.rotatePagesThreshold == nil)
        #expect(config.maxImagePixels == nil)
        #expect(config.colorConversionStrategy == nil)
        #expect(config.appTitle == nil)
        #expect(config.appLogo == nil)
        #expect(config.barcodesEnabled == nil)
        #expect(config.barcodeEnableTiffSupport == nil)
        #expect(config.barcodeString == nil)
        #expect(config.barcodeRetainSplitPages == nil)
        #expect(config.barcodeEnableAsn == nil)
        #expect(config.barcodeAsnPrefix == nil)
        #expect(config.barcodeUpscale == nil)
        #expect(config.barcodeDpi == nil)
        #expect(config.barcodeMaxPages == nil)
        #expect(config.barcodeEnableTag == nil)
    }

    @Test func testPartialConfigurationDecoding() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_partial.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that partial fields are decoded and others use defaults
        #expect(config.id == 3)
        #expect(config.appTitle == "Custom Paperless")
        #expect(config.barcodesEnabled == false)
        #expect(config.deskew == false)
        #expect(config.language == "de")
        #expect(config.barcodeDpi == 150)

        // Test that missing fields are nil
        #expect(config.userArgs == nil)
        #expect(config.outputType == nil)
        #expect(config.pages == nil)
        #expect(config.rotatePages == nil)
        #expect(config.barcodeEnableAsn == nil)
        #expect(config.barcodeAsnPrefix == nil)
    }

    @Test func testNullValueHandling() throws {
        let data = try #require(testData("Data/AppConfiguration/app_config_null_values.json"))
        let configs = try decoder.decode([AppConfiguration].self, from: data)

        #expect(configs.count == 1)
        let config = configs[0]

        // Test that null values are handled correctly
        #expect(config.id == 4)
        #expect(config.userArgs == nil) // null string remains nil
        #expect(config.pages == nil) // null optional remains nil
        #expect(config.imageDpi == nil) // null optional remains nil
        #expect(config.barcodeDpi == nil) // null optional remains nil
        #expect(config.barcodeMaxPages == nil) // null optional remains nil
        #expect(config.appTitle == "Null Test") // non-null value preserved
        #expect(config.deskew == true) // non-null boolean preserved
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
        #expect(config.appTitle == "Single Config")
        #expect(config.barcodesEnabled == true)
        #expect(config.language == "fr")
        #expect(config.mode == nil) // missing field is nil
        #expect(config.pages == nil) // missing field is nil
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
        // These large numbers should be handled gracefully
        #expect(config.pages != nil)
        #expect(config.imageDpi != nil)
        #expect(config.maxImagePixels != nil)
        #expect(config.maxImagePixels! > 0)
    }
}
