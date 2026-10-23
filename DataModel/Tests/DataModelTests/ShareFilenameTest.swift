//
//  ShareFilenameTest.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct ShareFilenameTest {
  static func makeDocument(
    title: String = "Invoice", original: String? = nil, archived: String? = nil
  ) -> Document {
    Document(
      id: 1, title: title, created: Date(timeIntervalSince1970: 0), tags: [],
      originalFileName: original, archivedFileName: archived)
  }

  @Test func archiveUsesArchivedName() {
    let doc = Self.makeDocument(original: "scan.png", archived: "scan.pdf")
    #expect(doc.shareFilename(original: false) == "scan.pdf")
    #expect(doc.shareFilename(original: true) == "scan.png")
  }

  @Test func archiveWithoutArchiveVersionUsesOriginalName() {
    let doc = Self.makeDocument(original: "notes.txt", archived: nil)
    #expect(doc.shareFilename(original: false) == "notes.txt")
  }

  @Test func noServerNameFallsBackToTitleWithoutExtension() {
    #expect(Self.makeDocument().shareFilename(original: false) == "Invoice")
    #expect(Self.makeDocument(title: "").shareFilename(original: true) == "document")
  }
}
