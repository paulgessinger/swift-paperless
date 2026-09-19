//
//  DocumentQueryPlacementTests.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct DocumentQueryPlacementTests {
  private static let base = Document(
    id: 1, title: "Invoice", asn: 7, documentType: 2, correspondent: 3,
    created: Date(timeIntervalSince1970: 1000), tags: [1, 2],
    added: Date(timeIntervalSince1970: 2000), modified: Date(timeIntervalSince1970: 3000),
    originalFileName: "a.pdf", archivedFileName: "a-archive.pdf", storagePath: 4,
    owner: .user(1), pageCount: 3, notes: NotesPayload(count: 1),
    customFields: CustomFieldRawEntryList([CustomFieldRawEntry(field: 1, value: .integer(5))]),
    versions: [DocumentVersion(id: 1, added: Date(timeIntervalSince1970: 2000), isRoot: true)],
    permissions: Permissions(view: .init(users: [2])))

  @Test(
    "An identical refresh can't move the document",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/689"))
  func identical() {
    #expect(!Self.base.queryPlacementMayDiffer(from: Self.base))
  }

  @Test("Tags are compared as a set, not in server order")
  func tagOrder() {
    var reordered = Self.base
    reordered.tags = [2, 1]
    #expect(!reordered.queryPlacementMayDiffer(from: Self.base))
  }

  @Test(
    "Every field a filter or sort can reference counts",
    arguments: [
      "title", "asn", "correspondent", "documentType", "storagePath", "tags", "created",
      "added", "modified", "owner", "permissions", "notes", "pageCount", "customFields",
      "originalFileName",
    ])
  func relevantField(_ field: String) throws {
    var changed = Self.base
    switch field {
    case "title": changed.title = "Receipt"
    case "asn": changed.asn = nil
    case "correspondent": changed.correspondent = 9
    case "documentType": changed.documentType = 9
    case "storagePath": changed.storagePath = nil
    case "tags": changed.tags = [1]
    case "created": changed.created = Date(timeIntervalSince1970: 1001)
    case "added": changed.added = nil
    case "modified": changed.modified = Date(timeIntervalSince1970: 3000.5)
    case "owner": changed.owner = .none
    case "permissions": changed.permissions = Permissions()
    case "notes": changed.notes = NotesPayload(count: 2)
    case "pageCount": changed.pageCount = 4
    case "customFields":
      changed.customFields = CustomFieldRawEntryList([
        CustomFieldRawEntry(field: 1, value: .integer(6))
      ])
    case "originalFileName": changed.originalFileName = "a.png"
    default: Issue.record("unhandled field \(field)")
    }
    #expect(changed.queryPlacementMayDiffer(from: Self.base))
  }

  @Test("Fields no filter or sort can reference don't count")
  func irrelevantFields() {
    var changed = Self.base
    changed.archivedFileName = "renamed.pdf"
    changed.versions.append(
      DocumentVersion(id: 2, added: Date(timeIntervalSince1970: 4000), isRoot: false))
    changed.setPermissions = Permissions(change: .init(users: [5]))
    #expect(!changed.queryPlacementMayDiffer(from: Self.base))
  }
}
