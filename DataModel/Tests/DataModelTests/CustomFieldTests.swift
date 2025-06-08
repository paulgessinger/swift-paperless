//
//  CustomFieldTests.swift
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
struct CustomFieldTests {
    @Test("Test decoding a select type custom field")
    func testDecodingSelectField() throws {
        let json = """
        {
            "id": 10,
            "name": "Custom select",
            "data_type": "select",
            "extra_data": {
                "select_options": [
                    {
                        "label": "Option 1",
                        "id": "9whg6VME2kWnDy9w"
                    },
                    {
                        "label": "Option 2",
                        "id": "VJc5Rk1yKQI95sFH"
                    }
                ],
                "default_currency": null
            },
            "document_count": 1
        }
        """.data(using: .utf8)!

        let field: CustomField = try decoder.decode(CustomField.self, from: json)

        #expect(field.id == 10)
        #expect(field.name == "Custom select")
        #expect(field.dataType == .select)
        #expect(field.documentCount == 1)
        #expect(field.extraData.defaultCurrency == nil)
        #expect(field.extraData.selectOptions.count == 2)
        #expect(field.extraData.selectOptions[0].label == "Option 1")
        #expect(field.extraData.selectOptions[0].id == "9whg6VME2kWnDy9w")
        #expect(field.extraData.selectOptions[1].label == "Option 2")
        #expect(field.extraData.selectOptions[1].id == "VJc5Rk1yKQI95sFH")
    }

    @Test("Test decoding a monetary type custom field")
    func testDecodingMonetaryField() throws {
        let json = """
        {
            "id": 5,
            "name": "Custom money USD explicit",
            "data_type": "monetary",
            "extra_data": {
                "select_options": [],
                "default_currency": "USD"
            },
            "document_count": 1
        }
        """.data(using: .utf8)!

        let field: CustomField = try decoder.decode(CustomField.self, from: json)

        #expect(field.id == 5)
        #expect(field.name == "Custom money USD explicit")
        #expect(field.dataType == .monetary)
        #expect(field.documentCount == 1)
        #expect(field.extraData.defaultCurrency == "USD")
        #expect(field.extraData.selectOptions.isEmpty)
    }

    @Test("Test decoding a custom field list")
    func testDecodingCustomFieldList() throws {
        let json = """
        {
            "count": 2,
            "next": null,
            "previous": null,
            "all": [10, 5],
            "results": [
                {
                    "id": 10,
                    "name": "Custom select",
                    "data_type": "select",
                    "extra_data": {
                        "select_options": [
                            {
                                "label": "Option 1",
                                "id": "9whg6VME2kWnDy9w"
                            }
                        ],
                        "default_currency": null
                    },
                    "document_count": 1
                },
                {
                    "id": 5,
                    "name": "Custom money USD explicit",
                    "data_type": "monetary",
                    "extra_data": {
                        "select_options": [],
                        "default_currency": "USD"
                    },
                    "document_count": 1
                }
            ]
        }
        """.data(using: .utf8)!

        let list: ListResponse<CustomField> = try decoder.decode(ListResponse<CustomField>.self, from: json)

        #expect(list.count == 2)
        #expect(list.next == nil)
        #expect(list.previous == nil)
        #expect(list.results.count == 2)

        // First result is select field
        let selectField = list.results[0]
        #expect(selectField.id == 10)
        #expect(selectField.dataType == .select)
        #expect(selectField.extraData.selectOptions.count == 1)

        // Second result is monetary field
        let monetaryField = list.results[1]
        #expect(monetaryField.id == 5)
        #expect(monetaryField.dataType == .monetary)
        #expect(monetaryField.extraData.defaultCurrency == "USD")
    }

    @Test("Test decoding all custom field data types")
    func testDecodingAllDataTypes() throws {
        let dataTypes = [
            "string",
            "url",
            "date",
            "boolean",
            "integer",
            "float",
            "monetary",
            "documentlink",
            "select",
        ]

        for typeStr in dataTypes {
            let json = """
            {
                "id": 1,
                "name": "Test field",
                "data_type": "\(typeStr)",
                "extra_data": {
                    "select_options": [],
                    "default_currency": null
                },
                "document_count": 0
            }
            """.data(using: .utf8)!

            let field = try decoder.decode(CustomField.self, from: json)
            #expect(field.dataType.rawValue == typeStr)
        }
    }

    @Test("Test encoding and decoding roundtrip")
    func testEncodingDecodingRoundtrip() throws {
        let originalField = CustomField(
            id: 1,
            name: "Test Field",
            dataType: .select,
            extraData: CustomField.ExtraData(
                selectOptions: [
                    CustomField.SelectOption(id: "opt1", label: "Option 1"),
                    CustomField.SelectOption(id: "opt2", label: "Option 2"),
                ],
                defaultCurrency: "EUR"
            ),
            documentCount: 5
        )

        let encoder = JSONEncoder()

        let encoded = try encoder.encode(originalField)
        let decoded = try decoder.decode(CustomField.self, from: encoded)

        #expect(decoded.id == originalField.id)
        #expect(decoded.name == originalField.name)
        #expect(decoded.dataType == originalField.dataType)
        #expect(decoded.documentCount == nil) // we don't encode the document count
        #expect(decoded.extraData.defaultCurrency == originalField.extraData.defaultCurrency)
        #expect(decoded.extraData.selectOptions.count == originalField.extraData.selectOptions.count)
        #expect(decoded.extraData.selectOptions[0].id == originalField.extraData.selectOptions[0].id)
        #expect(decoded.extraData.selectOptions[0].label == originalField.extraData.selectOptions[0].label)
        #expect(decoded.extraData.selectOptions[1].id == originalField.extraData.selectOptions[1].id)
        #expect(decoded.extraData.selectOptions[1].label == originalField.extraData.selectOptions[1].label)
    }

    @Test("Test decoding unknown data type")
    func testDecodingUnknownDataType() throws {
        let json = """
        {
            "id": 1,
            "name": "Future field type",
            "data_type": "future_type",
            "extra_data": {
                "select_options": [],
                "default_currency": null
            },
            "document_count": 0
        }
        """.data(using: .utf8)!

        let field = try decoder.decode(CustomField.self, from: json)

        #expect(field.dataType == .other("future_type"))
    }
}
