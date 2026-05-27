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

  @Test("Two versions: newest by `added` wins for currentVersionID, root wins for rootVersionID")
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
}
