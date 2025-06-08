//
//  CustomFieldValueTests.swift
//  DataModelTests
//
//  Created by AI Assistant on 26.03.2024.
//

import Common
@testable import DataModel
import Foundation
import Testing

private let decoder = makeDecoder(tz: .current)

@Suite
struct CustomFieldValueTests {
    @Test("Test decoding raw string value")
    func testDecodingRawStringValue() throws {
        let json = """
        {
            "field": 7,
            "value": "Super duper text"
        }
        """.data(using: .utf8)!

        let entry = try decoder.decode(CustomFieldRawEntry.self, from: json)

        #expect(entry.field == 7)
        #expect(entry.value == .string("Super duper text"))
    }

    @Test("Test decoding raw number value")
    func testDecodingRawNumberValue() throws {
        let json = """
        {
            "field": 1,
            "value": 123.45
        }
        """.data(using: .utf8)!

        let entry = try decoder.decode(CustomFieldRawEntry.self, from: json)

        #expect(entry.field == 1)
        #expect(entry.value == .number(123.45))
    }

    @Test("Test decoding raw integer value")
    func testDecodingRawIntegerValue() throws {
        let json = """
        {
            "field": 4,
            "value": 42
        }
        """.data(using: .utf8)!

        let entry = try decoder.decode(CustomFieldRawEntry.self, from: json)

        #expect(entry.field == 4)
        #expect(entry.value == .integer(42))
    }

    @Test("Test decoding raw boolean value")
    func testDecodingRawBooleanValue() throws {
        let json = """
        {
            "field": 2,
            "value": true
        }
        """.data(using: .utf8)!

        let entry = try decoder.decode(CustomFieldRawEntry.self, from: json)

        #expect(entry.field == 2)
        #expect(entry.value == .boolean(true))
    }

    @Test("Test decoding raw id list value")
    func testDecodingRawIdListValue() throws {
        let json = """
        {
            "field": 9,
            "value": [1, 6]
        }
        """.data(using: .utf8)!

        let entry = try decoder.decode(CustomFieldRawEntry.self, from: json)

        #expect(entry.field == 9)
        #expect(entry.value == .idList([1, 6]))
    }

    @Test("Test decoding invalid value type")
    func testDecodingInvalidValueType() throws {
        let json = """
        {
            "field": 1,
            "value": {
                "some": "object"
            }
        }
        """.data(using: .utf8)!

        // Type is invalid but we don't throw an error for robustness
        let entry = try decoder.decode(CustomFieldRawEntry.self, from: json)
        #expect(entry.value == .unknown)
    }

    @Test("Test encoding string value")
    func testEncodingStringValue() throws {
        struct StringTest: Decodable {
            let field: UInt
            let value: String
        }

        let entry = CustomFieldRawEntry(field: 1, value: .string("test"))
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(StringTest.self, from: encoded)

        #expect(decoded.field == 1)
        #expect(decoded.value == "test")
    }

    @Test("Test encoding number value")
    func testEncodingNumberValue() throws {
        struct NumberTest: Decodable {
            let field: UInt
            let value: Double
        }

        let entry = CustomFieldRawEntry(field: 2, value: .number(123.45))
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(NumberTest.self, from: encoded)

        #expect(decoded.field == 2)
        #expect(decoded.value == 123.45)
    }

    @Test("Test encoding integer value")
    func testEncodingIntegerValue() throws {
        struct IntegerTest: Decodable {
            let field: UInt
            let value: Int
        }

        let entry = CustomFieldRawEntry(field: 3, value: .integer(42))
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(IntegerTest.self, from: encoded)

        #expect(decoded.field == 3)
        #expect(decoded.value == 42)
    }

    @Test("Test encoding boolean value")
    func testEncodingBooleanValue() throws {
        struct BooleanTest: Decodable {
            let field: UInt
            let value: Bool
        }

        let entry = CustomFieldRawEntry(field: 4, value: .boolean(true))
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(BooleanTest.self, from: encoded)

        #expect(decoded.field == 4)
        #expect(decoded.value == true)
    }

    @Test("Test encoding id list value")
    func testEncodingIdListValue() throws {
        struct IdListTest: Decodable {
            let field: UInt
            let value: [UInt]
        }

        let entry = CustomFieldRawEntry(field: 5, value: .idList([1, 2, 3]))
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(IdListTest.self, from: encoded)

        #expect(decoded.field == 5)
        #expect(decoded.value == [1, 2, 3])
    }

    @Test("Test encoding unknown value")
    func testEncodingUnknownValue() throws {
        struct UnknownTest: Decodable {
            let field: UInt
            let value: String?
        }

        let entry = CustomFieldRawEntry(field: 6, value: .unknown)

        #expect(throws: CustomFieldUnknownValue.self) {
            _ = try JSONEncoder().encode(entry)
        }
    }

    @Test("Test decoding raw value list")
    func testDecodingRawValueList() throws {
        let json = """
        {
            "custom_fields": [
                {
                    "value": [
                        1,
                        6
                    ],
                    "field": 9
                },
                {
                    "value": "USD1000.00",
                    "field": 5
                },
                {
                    "value": "EUR1000.00",
                    "field": 6
                },
                {
                    "value": "nGAGi8292Tbzlwye",
                    "field": 10
                },
                {
                    "value": "https://paperless-ngx.com",
                    "field": 8
                },
                {
                    "value": 42,
                    "field": 4
                },
                {
                    "value": true,
                    "field": 2
                },
                {
                    "value": "Super duper text",
                    "field": 7
                },
                {
                    "value": "2025-06-25",
                    "field": 3
                },
                {
                    "value": 123.45,
                    "field": 1
                }
            ]
        }
        """.data(using: .utf8)!

        struct Decoded: Codable {
            var custom_fields: CustomFieldRawValueList
        }

        let decoded = try decoder.decode(Decoded.self, from: json)
        let values = decoded.custom_fields.values

        #expect(values.count == 10)
        #expect(values[0].value == .idList([1, 6]))
        #expect(values[0].field == 9)
        #expect(values[1].value == .string("USD1000.00"))
        #expect(values[1].field == 5)
        #expect(values[2].value == .string("EUR1000.00"))
        #expect(values[2].field == 6)
        #expect(values[3].value == .string("nGAGi8292Tbzlwye"))
        #expect(values[3].field == 10)
        #expect(values[4].value == .string("https://paperless-ngx.com"))
        #expect(values[4].field == 8)
        #expect(values[5].value == .integer(42))
        #expect(values[5].field == 4)
        #expect(values[6].value == .boolean(true))
        #expect(values[6].field == 2)
        #expect(values[7].value == .string("Super duper text"))
        #expect(values[7].field == 7)
        #expect(values[8].value == .string("2025-06-25"))
        #expect(values[8].field == 3)
        #expect(values[9].value == .number(123.45))
        #expect(values[9].field == 1)

        #expect(decoded.custom_fields.hasUnknown == false)
    }

    @Test("Test decoding raw value list with unknown value")
    func testDecodingRawValueListWithUnknownValue() throws {
        let json = """
        {
            "custom_fields": [
                {
                    "value": [
                        1,
                        6
                    ],
                    "field": 9
                },
                {
                    "value": {
                        "some": "object"
                    },
                    "field": 1
                }
            ]
        }
        """.data(using: .utf8)!

        struct Decoded: Codable {
            var custom_fields: CustomFieldRawValueList
        }

        let decoded = try decoder.decode(Decoded.self, from: json)
        let values = decoded.custom_fields.values

        #expect(values.count == 2)
        #expect(values[0].value == .idList([1, 6]))
        #expect(values[0].field == 9)
        #expect(values[1].value == .unknown)
        #expect(values[1].field == 1)

        #expect(decoded.custom_fields.hasUnknown == true)

        #expect(throws: CustomFieldUnknownValue.self) {
            _ = try JSONEncoder().encode(decoded)
        }
    }
}
