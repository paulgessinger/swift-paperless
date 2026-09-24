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

  @Test("A changed modified date counts, down to sub-second precision")
  func modifiedChanged() {
    var changed = Self.base
    changed.modified = Date(timeIntervalSince1970: 3000.5)
    #expect(changed.queryPlacementMayDiffer(from: Self.base))
  }

  @Test("Gaining or losing a modified date counts")
  func modifiedAppearsOrDisappears() {
    var missing = Self.base
    missing.modified = nil
    #expect(missing.queryPlacementMayDiffer(from: Self.base))
    #expect(Self.base.queryPlacementMayDiffer(from: missing))
  }

  @Test("Other fields don't count on their own: the server bumps modified with them")
  func otherFieldsFollowModified() {
    var changed = Self.base
    changed.title = "Receipt"
    changed.tags = [1]
    changed.correspondent = 9
    changed.archivedFileName = "renamed.pdf"
    #expect(!changed.queryPlacementMayDiffer(from: Self.base))
  }
}
