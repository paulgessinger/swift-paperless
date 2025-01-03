//
//  DocumentModeltest.swift
//  DataModel
//
//  Created by Paul Gessinger on 02.01.25.
//
import Common
@testable import DataModel
import Foundation
import Testing

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

        #expect(dateApprox(document.created, datetime(year: 2024, month: 12, day: 21, hour: 0, minute: 0, second: 0, tz: tz)))
        #expect(try dateApprox(#require(document.modified), datetime(year: 2024, month: 12, day: 21, hour: 21, minute: 41, second: 49, tz: tz)))
        #expect(try dateApprox(#require(document.added), datetime(year: 2024, month: 12, day: 21, hour: 21, minute: 26, second: 36, tz: tz)))

        #expect(document.asn == 666)
        #expect(document.owner == 2)
        #expect(document.notes.count == 1)

        let note = try #require(document.notes.first)
        #expect(note.id == 40)
        #expect(note.note == "hallo")
        #expect(dateApprox(note.created, datetime(year: 2025, month: 1, day: 2, hour: 16, minute: 3, second: 36, tz: tz)))

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

    @Test
    func testSetPermissionsKey() throws {
        var document = Document(id: 123, title: "hallo", created: .now, tags: [], notes: [])
        document.added = .now
        document.modified = .now
        document.permissions = Permissions(view: Permissions.Set(users: [1], groups: [2]), change: Permissions.Set(users: [3], groups: [4]))

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
        case owner

        var keyPath: WritableKeyPath<Document, UInt?> {
            switch self {
            case .correspondent: \.correspondent
            case .documentType: \.documentType
            case .storagePath: \.storagePath
            case .asn: \.asn
            case .owner: \.owner
            }
        }
    }

    @Test("Tests that null values are decoded as nil-valued optionals", arguments: NilComponent.allCases)
    func testNilComponentsDecode(component: NilComponent) throws {
        let data = try #require(testData("Data/Document/full.json"))
        let raw = try #require(String(data: data, encoding: .utf8))
        let ex = try Regex("\"\(component.rawValue)\": ?(.*)")
        let withNil = try #require(raw.replacing(ex, with: "\"\(component.rawValue)\": null,").data(using: .utf8))
        let document = try decoder.decode(Document.self, from: withNil)
        #expect(document[keyPath: component.keyPath] == nil)
    }

    @Test("Tests that nil components are written out as literal null values", arguments: NilComponent.allCases)
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
}
