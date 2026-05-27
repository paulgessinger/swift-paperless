//
//  ApiCustomFieldTest.swift
//  Networking
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

private let decoder = makeDecoder(tz: .current)

@Suite("ApiCustomFieldTest")
struct ApiCustomFieldTest {
  @Test("Decode a select-type custom field")
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

    let field = try decoder.decode(ApiCustomField.self, from: json).domain

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

  @Test("Decode a monetary-type custom field")
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

    let field = try decoder.decode(ApiCustomField.self, from: json).domain

    #expect(field.id == 5)
    #expect(field.name == "Custom money USD explicit")
    #expect(field.dataType == .monetary)
    #expect(field.documentCount == 1)
    #expect(field.extraData.defaultCurrency == "USD")
    #expect(field.extraData.selectOptions.isEmpty)
  }

  @Test("Decode a custom field list")
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

    let list = try decoder.decode(ListResponse<ApiCustomField>.self, from: json)
    let results = list.results.map(\.domain)

    #expect(list.count == 2)
    #expect(list.next == nil)
    #expect(list.previous == nil)
    #expect(results.count == 2)

    let selectField = results[0]
    #expect(selectField.id == 10)
    #expect(selectField.dataType == .select)
    #expect(selectField.extraData.selectOptions.count == 1)

    let monetaryField = results[1]
    #expect(monetaryField.id == 5)
    #expect(monetaryField.dataType == .monetary)
    #expect(monetaryField.extraData.defaultCurrency == "USD")
  }

  @Test(
    "Decode custom fields with each data type",
    arguments: [
      "string",
      "longtext",
      "url",
      "date",
      "boolean",
      "integer",
      "float",
      "monetary",
      "documentlink",
      "select",
    ]
  )
  func testDecodingFieldsWithAllDataTypes(typeStr: String) throws {
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

    let field = try decoder.decode(ApiCustomField.self, from: json).domain
    #expect(field.dataType.rawValue == typeStr)
    #expect(field.dataType != .other(typeStr))
  }

  @Test("Decode unknown data type as .other(...)")
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

    let field = try decoder.decode(ApiCustomField.self, from: json).domain
    #expect(field.dataType == .other("future_type"))
  }

  @Test("Decode tolerates null entries in select_options")
  func testDecodingStringFieldWithNullSelectOptions() throws {
    let json = """
      {
        "id": 3,
        "name": "Reference number",
        "data_type": "string",
        "extra_data": {
          "select_options": [
            null
          ],
          "default_currency": null
        },
        "document_count": 2
      }
      """.data(using: .utf8)!

    let field = try decoder.decode(ApiCustomField.self, from: json).domain

    #expect(field.id == 3)
    #expect(field.name == "Reference number")
    #expect(field.dataType == .string)
    #expect(field.documentCount == 2)
    #expect(field.extraData.defaultCurrency == nil)
    #expect(field.extraData.selectOptions.isEmpty)
  }
}

@Suite("CustomFieldDataType raw values")
struct CustomFieldDataTypeRawTest {
  @Test("All data types round-trip raw values")
  func testDecodingAllDataTypes() throws {
    #expect(try #require(CustomFieldDataType(rawValue: "string")) == .string)
    #expect(try #require(CustomFieldDataType(rawValue: "longtext")) == .longText)
    #expect(try #require(CustomFieldDataType(rawValue: "url")) == .url)
    #expect(try #require(CustomFieldDataType(rawValue: "date")) == .date)
    #expect(try #require(CustomFieldDataType(rawValue: "boolean")) == .boolean)
    #expect(try #require(CustomFieldDataType(rawValue: "integer")) == .integer)
    #expect(try #require(CustomFieldDataType(rawValue: "float")) == .float)
    #expect(try #require(CustomFieldDataType(rawValue: "monetary")) == .monetary)
    #expect(try #require(CustomFieldDataType(rawValue: "documentlink")) == .documentLink)
    #expect(try #require(CustomFieldDataType(rawValue: "select")) == .select)
  }
}
