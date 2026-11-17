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
    title: String = "Invoice 42", original: String? = nil, archived: String? = nil,
    mimeType: String? = nil
  ) -> Document {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let created = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1))!
    return Document(
      id: 1, title: title, created: created, tags: [],
      originalFileName: original, archivedFileName: archived, mimeType: mimeType)
  }

  @Test func archiveAndOriginalUseServerStyleName() {
    let doc = Self.makeDocument(original: "scan_0042.png", archived: "stale name.pdf")
    #expect(
      doc.shareFilename(original: false, correspondentName: "ACME")
        == "2024-03-01 ACME Invoice 42.pdf")
    #expect(
      doc.shareFilename(original: true, correspondentName: "ACME")
        == "2024-03-01 ACME Invoice 42.png")
  }

  @Test func originalExtensionComesFromMimeType() {
    let doc = Self.makeDocument(original: "photo.JPEG", archived: "x.pdf", mimeType: "image/jpeg")
    #expect(
      doc.shareFilename(original: true, correspondentName: nil) == "2024-03-01 Invoice 42.jpg")
    #expect(
      doc.shareFilename(original: false, correspondentName: nil) == "2024-03-01 Invoice 42.pdf")
  }

  @Test func unknownMimeTypeFallsBackToUploadExtension() {
    let doc = Self.makeDocument(original: "photo.JPEG", mimeType: "application/x-unknown")
    #expect(
      doc.shareFilename(original: true, correspondentName: nil) == "2024-03-01 Invoice 42.JPEG")
  }

  @Test func archiveWithoutArchiveVersionUsesOriginalExtension() {
    let doc = Self.makeDocument(original: "notes.txt", archived: nil)
    #expect(
      doc.shareFilename(original: false, correspondentName: nil) == "2024-03-01 Invoice 42.txt")
  }

  @Test func noOriginalNameHasNoExtension() {
    #expect(
      Self.makeDocument().shareFilename(original: true, correspondentName: nil)
        == "2024-03-01 Invoice 42")
    #expect(
      Self.makeDocument(title: "").shareFilename(original: true, correspondentName: nil)
        == "2024-03-01")
  }

  @Test func invalidCharactersAreReplaced() {
    let doc = Self.makeDocument(title: "a/b: c?", original: "x.pdf")
    #expect(
      doc.shareFilename(original: true, correspondentName: "<Me>") == "2024-03-01 -Me- a-b- c-.pdf")
  }

  @Test func longTitleIsShortenedBeforeTheExtension() {
    let doc = Self.makeDocument(title: String(repeating: "ä", count: 300), original: "x.pdf")
    let name = doc.shareFilename(original: true, correspondentName: nil)
    #expect(name.utf8.count <= 255)
    #expect(name.hasSuffix("ä.pdf"))
  }
}
