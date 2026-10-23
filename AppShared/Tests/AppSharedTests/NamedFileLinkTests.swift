//
//  NamedFileLinkTests.swift
//  AppShared
//

import Foundation
import Testing

@testable import AppShared

@Suite
struct NamedFileLinkTests {
  private func makeCanonical(_ contents: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("NamedFileLinkTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("archive.pdf")
    try Data(contents.utf8).write(to: url)
    return url
  }

  @Test func stagesUnderTheGivenName() throws {
    let canonical = try makeCanonical("hello")
    let staged = try #require(NamedFileLink.stage(canonical, as: "notes.txt"))
    #expect(staged.lastPathComponent == "notes.txt")
    #expect(try String(contentsOf: staged, encoding: .utf8) == "hello")
  }

  @Test func keepsItsBytesWhenTheCanonicalFileIsReplaced() throws {
    let canonical = try makeCanonical("old")
    let staged = try #require(NamedFileLink.stage(canonical, as: "scan.png"))
    let replacement = canonical.deletingLastPathComponent().appendingPathComponent("new.tmp")
    try Data("new".utf8).write(to: replacement)
    _ = try FileManager.default.replaceItemAt(canonical, withItemAt: replacement)
    #expect(try String(contentsOf: staged, encoding: .utf8) == "old")
  }

  @Test func sanitizesTheName() {
    #expect(NamedFileLink.sanitize("a/b\u{0}c.pdf") == "abc.pdf")
    #expect(NamedFileLink.sanitize("  ") == "document")
  }
}
