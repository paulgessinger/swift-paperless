//
//  DocumentModeltest.swift
//  DataModel
//
//  Created by Paul Gessinger on 02.01.25.
//
import Common
import Foundation
import Testing

@testable import DataModel

private let tz = TimeZone(secondsFromGMT: 60 * 60)!
private let decoder = makeDecoder(tz: tz)

@Suite
struct DocumentModelTest {
  @Test
  func testDecodeNonNil() throws {
    let data = try #require(testData("Data/Document/full.json"))
    let document = try decoder.decode(Document.self, from: data)

    #expect(document.id == 2724)
    #expect(document.correspondent == 123)
    #expect(document.documentType == 5)
    #expect(document.storagePath == 1)
    #expect(document.title == "Quittung")
    #expect(document.tags == [1, 2, 3])

    #expect(
      dateApprox(
        document.created, datetime(year: 2024, month: 12, day: 21, hour: 0, minute: 0, second: 0)))
    #expect(
      try dateApprox(
        #require(document.modified),
        datetime(year: 2024, month: 12, day: 21, hour: 21, minute: 41, second: 49, tz: tz)))
    #expect(
      try dateApprox(
        #require(document.added),
        datetime(year: 2024, month: 12, day: 21, hour: 21, minute: 26, second: 36, tz: tz)))

    #expect(document.asn == 666)
    #expect(document.owner == .user(2))
    #expect(document.notes.count == 1)

    #expect(document.userCanChange == true)

    // No permissions by default
    #expect(document.permissions == nil)
  }

  @Test("Tests that new notes are correctly decoded")
  // After bundled notes payload changed: https://github.com/paperless-ngx/paperless-ngx/pull/8948
  func testNewNotesDecode() throws {
    let data = try #require(testData("Data/Document/full_new_notes.json"))
    let document = try decoder.decode(Document.self, from: data)

    #expect(document.id == 2724)
    #expect(document.correspondent == 123)
    #expect(document.documentType == 5)
    #expect(document.storagePath == 1)
    #expect(document.title == "Quittung")
    #expect(document.tags == [1, 2, 3])

    #expect(
      dateApprox(
        document.created, datetime(year: 2024, month: 12, day: 21, hour: 0, minute: 0, second: 0)))
    #expect(
      try dateApprox(
        #require(document.modified),
        datetime(year: 2024, month: 12, day: 21, hour: 21, minute: 41, second: 49, tz: tz)))
    #expect(
      try dateApprox(
        #require(document.added),
        datetime(year: 2024, month: 12, day: 21, hour: 21, minute: 26, second: 36, tz: tz)))

    #expect(document.asn == 666)
    #expect(document.owner == .user(2))
    #expect(document.notes.count == 1)

    #expect(document.userCanChange == true)

    // No permissions by default
    #expect(document.permissions == nil)
  }

  @Test("Tests that the user_can_change field is correctly decoded, even if not present")
  func testUserCanChangeDefault() throws {
    let data = try #require(testData("Data/Document/full_no_user_can_change.json"))
    let document = try decoder.decode(Document.self, from: data)
    #expect(document.userCanChange == true)
  }

  @Test("Tests that the user_can_change field is correctly decoded, even if it is false")
  func testUserCanChangeIsFalse() throws {
    let data = try #require(testData("Data/Document/full_no_user_can_change_false.json"))
    let document = try decoder.decode(Document.self, from: data)
    #expect(document.userCanChange == false)
  }

  @Test
  func testSetPermissionsKey() throws {
    var document = Document(id: 123, title: "hallo", created: .now, tags: [])
    document.added = .now
    document.modified = .now
    document.permissions = Permissions(
      view: Permissions.Set(users: [1], groups: [2]),
      change: Permissions.Set(users: [3], groups: [4]))

    let json = try JSONEncoder().encode(document)

    struct Helper: Decodable {
      var set_permissions: Permissions
    }

    let decoded = try JSONDecoder().decode(Helper.self, from: json)
    #expect(decoded.set_permissions == document.permissions)

    let string = try #require(String(data: json, encoding: .utf8))

    let absent = { (key: String) -> Bool in
      let ex = try Regex("\"\(key)\":")
      return string.contains(ex) == false
    }

    #expect(try absent("notes"))
    #expect(try absent("user_can_change"))
    #expect(try absent("permissions"))
    #expect(try absent("added"))
    #expect(try absent("modified"))
  }

  @Test
  func testPermissionsDecode() throws {
    let data = try #require(testData("Data/Document/full_with_perms.json"))
    let document = try decoder.decode(Document.self, from: data)

    let perms = try #require(document.permissions)

    #expect(perms.change == Permissions.Set(users: [1], groups: []))
    #expect(perms.view == Permissions.Set(users: [], groups: [1]))
  }

  enum NilComponent: String, CaseIterable {
    case correspondent
    case documentType = "document_type"
    case storagePath = "storage_path"
    case asn = "archive_serial_number"

    var keyPath: WritableKeyPath<Document, UInt?> {
      switch self {
      case .correspondent: \.correspondent
      case .documentType: \.documentType
      case .storagePath: \.storagePath
      case .asn: \.asn
      }
    }
  }

  @Test(
    "Tests that null values are decoded as nil-valued optionals", arguments: NilComponent.allCases)
  func testNilComponentsDecode(component: NilComponent) throws {
    let data = try #require(testData("Data/Document/full.json"))
    let raw = try #require(String(data: data, encoding: .utf8))
    let ex = try Regex("\"\(component.rawValue)\": ?(.*)")
    let withNil = try #require(
      raw.replacing(ex, with: "\"\(component.rawValue)\": null,").data(using: .utf8))
    let document = try decoder.decode(Document.self, from: withNil)
    #expect(document[keyPath: component.keyPath] == nil)
  }

  @Test(
    "Tests that nil components are written out as literal null values",
    arguments: NilComponent.allCases)
  func testNilComponentsEncode(component: NilComponent) throws {
    let data = try #require(testData("Data/Document/full.json"))
    var document = try decoder.decode(Document.self, from: data)

    #expect(document[keyPath: component.keyPath] != nil)
    document[keyPath: component.keyPath] = nil

    let json = try #require(String(data: JSONEncoder().encode(document), encoding: .utf8))
    let ex = try Regex("\"\(component.rawValue)\": ?null")

    let match = try ex.firstMatch(in: json)
    #expect(match != nil)
  }

  @Test("Test owner encoding none")
  func testOwnerEncoding() throws {
    let document = Document(id: 123, title: "hallo", created: .now, tags: [], owner: .none)

    let json = try JSONEncoder().encode(document)
    let s = try #require(String(data: json, encoding: .utf8))
    #expect(s.contains("\"owner\":null"))
  }

  @Test("Test owner encoding unset")
  func testOwnerEncodingUnset() throws {
    let document = Document(id: 123, title: "hallo", created: .now, tags: [], owner: .unset)
    let json = try JSONEncoder().encode(document)
    let s = try #require(String(data: json, encoding: .utf8))
    #expect(s.contains("\"owner\":null"))
  }

  @Test("Encode document model")
  func testEncodeDocument() throws {
    let data = try #require(testData("Data/Document/full.json"))
    let document = try decoder.decode(Document.self, from: data)

    // mirror `ApiRepository`
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      let formatter = ISO8601DateFormatter()
      let tz = TimeZone(secondsFromGMT: 60 * 60)!
      formatter.timeZone = tz
      let dateString = formatter.string(from: date)
      var container = encoder.singleValueContainer()
      try container.encode(dateString)
    }

    let encoded = try encoder.encode(document)
    let s = try #require(String(data: encoded, encoding: .utf8))
    #expect(s.contains("\"created\":\"2024-12-21\""))
  }

  @Test("Test decoding document with custom fields")
  func testDecodeDocumentWithCustomFields() throws {
    let data = try #require(testData("Data/CustomFields/document_with_custom_fields.json"))
    let document = try decoder.decode(Document.self, from: data)

    #expect(document.id == 3)
    #expect(document.title == "demo yo xy")
    #expect(document.owner == .user(4))

    let customFields = document.customFields
    #expect(customFields.count == 10)

    // Document link field
    #expect(customFields[0].field == 9)
    #expect(customFields[0].value == .idList([1, 6]))

    // Monetary fields
    #expect(customFields[1].field == 5)
    #expect(customFields[1].value == .string("USD1000.00"))
    #expect(customFields[2].field == 6)
    #expect(customFields[2].value == .string("EUR1000.00"))

    // String field
    #expect(customFields[3].field == 10)
    #expect(customFields[3].value == .string("nGAGi8292Tbzlwye"))

    // URL field
    #expect(customFields[4].field == 8)
    #expect(customFields[4].value == .string("https://paperless-ngx.com"))

    // Integer field
    #expect(customFields[5].field == 4)
    #expect(customFields[5].value == .integer(42))

    // Boolean field
    #expect(customFields[6].field == 2)
    #expect(customFields[6].value == .boolean(true))

    // Text field
    #expect(customFields[7].field == 7)
    #expect(customFields[7].value == .string("Super duper text"))

    // Date field
    #expect(customFields[8].field == 3)
    #expect(customFields[8].value == .string("2025-06-25"))

    // Float field
    #expect(customFields[9].field == 1)
    #expect(customFields[9].value == .float(123.45))
  }

  @Test(
    "Test decoding document with date-based title",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/360", id: 360)
  )
  func testDecodeDocumentWithDateTitle() throws {
    let jsonString = """
      {"id":17,"correspondent":null,"document_type":null,"storage_path":null,"title":"1990-10-21","content":"1990-10-21","tags":[1],"created":"1990-10-21","created_date":"1990-10-21","modified":"2026-01-16T19:15:49.032469Z","added":"2026-01-16T19:14:45.591218Z","deleted_at":null,"archive_serial_number":null,"original_file_name":"1990-10-21.pdf","archived_file_name":"1990-10-21 1990-10-21.pdf","owner":3,"user_can_change":true,"is_shared_by_requester":false,"notes":[],"custom_fields":[],"page_count":1,"mime_type":"application/pdf"}
      """
    let data = try #require(jsonString.data(using: .utf8))
    let document = try decoder.decode(Document.self, from: data)

    #expect(document.id == 17)
    #expect(document.correspondent == nil)
    #expect(document.documentType == nil)
    #expect(document.storagePath == nil)
    #expect(document.title == "1990-10-21")
    #expect(document.tags == [1])
    #expect(
      dateApprox(
        document.created,
        datetime(year: 1990, month: 10, day: 21, hour: 0, minute: 0, second: 0, tz: tz)))
    #expect(document.asn == nil)
    #expect(document.owner == .user(3))
    #expect(document.userCanChange == true)
    #expect(document.customFields.isEmpty)
    #expect(document.notes.count == 0)
    #expect(document.pageCount == 1)
  }
}
