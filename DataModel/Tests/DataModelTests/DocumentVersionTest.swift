//
//  DocumentVersionTest.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct DocumentVersionTest {
  static func makeDocument(id: UInt = 16, versions: [DocumentVersion] = []) -> Document {
    Document(
      id: id, title: "doc",
      created: Date(timeIntervalSince1970: 0), tags: [],
      versions: versions)
  }

  @Test(
    "Empty versions array falls back to the document id (doc id == root version id server-side)")
  func emptyVersionsFallsBackToDocumentId() {
    let doc = Self.makeDocument(id: 42, versions: [])
    #expect(doc.currentVersionID == 42)
    #expect(doc.rootVersionID == 42)
  }

  @Test("Single version: currentVersionID is that version, rootVersionID respects isRoot")
  func singleVersion() {
    let doc = Self.makeDocument(
      id: 16,
      versions: [
        DocumentVersion(
          id: 16, added: Date(timeIntervalSince1970: 1000),
          label: "V1", isRoot: true)
      ])
    #expect(doc.currentVersionID == 16)
    #expect(doc.rootVersionID == 16)
  }

  @Test("Two versions: highest id wins for currentVersionID, root wins for rootVersionID")
  func twoVersionsPicksNewestAndRoot() {
    let doc = Self.makeDocument(
      id: 16,
      versions: [
        DocumentVersion(
          id: 16, added: Date(timeIntervalSince1970: 1_000),
          label: "V1", isRoot: true),
        DocumentVersion(
          id: 35, added: Date(timeIntervalSince1970: 2_000),
          label: "V2", isRoot: false),
      ])
    #expect(doc.currentVersionID == 35)
    #expect(doc.rootVersionID == 16)
  }

  @Test("Version order in the array does not change resolution")
  func versionOrderIndependent() {
    let v1 = DocumentVersion(
      id: 16, added: Date(timeIntervalSince1970: 1_000),
      label: "V1", isRoot: true)
    let v2 = DocumentVersion(
      id: 35, added: Date(timeIntervalSince1970: 2_000),
      label: "V2", isRoot: false)

    let docAscending = Self.makeDocument(versions: [v1, v2])
    let docDescending = Self.makeDocument(versions: [v2, v1])

    #expect(docAscending.currentVersionID == docDescending.currentVersionID)
    #expect(docAscending.rootVersionID == docDescending.rootVersionID)
  }

  // paperless resolves the default version with `order_by("-id").first()`
  // (documents/versioning.py, get_latest_version_for_root), so a newer row with
  // an older `added` must still win. `added` can trail id after an import or a
  // restore preserves the original timestamps.
  @Test("Highest id wins even when its `added` timestamp is older")
  func idWinsOverAddedTimestamp() {
    let doc = Self.makeDocument(
      id: 16,
      versions: [
        DocumentVersion(
          id: 16, added: Date(timeIntervalSince1970: 9_000),
          label: "V1", isRoot: true),
        DocumentVersion(
          id: 35, added: Date(timeIntervalSince1970: 1_000),
          label: "V2 (restored, original timestamp preserved)", isRoot: false),
      ])
    #expect(doc.currentVersionID == 35)
    #expect(doc.rootVersionID == 16)
  }

  // Ordering by id is total because ids are unique primary keys. Ordering by
  // `added` was not: `max(by:)` returns an unspecified element among ties, so
  // `versionOrderIndependent` above did not actually hold for equal timestamps.
  @Test("Equal `added` timestamps still resolve deterministically")
  func equalAddedTimestampsResolveByID() {
    let sameInstant = Date(timeIntervalSince1970: 1_000)
    let v1 = DocumentVersion(id: 16, added: sameInstant, label: "V1", isRoot: true)
    let v2 = DocumentVersion(id: 35, added: sameInstant, label: "V2", isRoot: false)

    #expect(Self.makeDocument(versions: [v1, v2]).currentVersionID == 35)
    #expect(Self.makeDocument(versions: [v2, v1]).currentVersionID == 35)
  }

  @Test("versionQueryID is nil without versions, so no redundant `?version=` is sent")
  func versionQueryIDOmittedWhenNoVersions() {
    #expect(Self.makeDocument(id: 42, versions: []).versionQueryID == nil)
  }

  @Test("versionQueryID matches currentVersionID once the server reports versions")
  func versionQueryIDPresentWithVersions() {
    let doc = Self.makeDocument(
      id: 16,
      versions: [
        DocumentVersion(
          id: 16, added: Date(timeIntervalSince1970: 1_000),
          label: "V1", isRoot: true),
        DocumentVersion(
          id: 35, added: Date(timeIntervalSince1970: 2_000),
          label: "V2", isRoot: false),
      ])
    #expect(doc.versionQueryID == 35)
    #expect(doc.versionQueryID == doc.currentVersionID)
  }
}
