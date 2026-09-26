//
//  DiskUsageTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

@Suite
struct DiskUsageTests {
  static func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("DiskUsageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static func write(_ byteCount: Int, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0xAB, count: byteCount).write(to: url)
  }

  @Test("A missing path measures as zero rather than failing")
  func missingPath() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("DiskUsageTests-missing-\(UUID().uuidString)")
    #expect(DiskUsage.measure(url) == .zero)
  }

  @Test("A directory walk counts every regular file, nested and hidden ones included")
  func directoryWalk() throws {
    let root = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Self.write(10_000, to: root.appendingPathComponent("a.bin"))
    try Self.write(5_000, to: root.appendingPathComponent("nested/deeper/b.bin"))
    try Self.write(100, to: root.appendingPathComponent(".hidden"))

    let usage = DiskUsage.measure(root)

    #expect(usage.files == 3)
    // Allocated size, so at least the logical length but block-rounded upward.
    #expect(usage.bytes >= 15_100)
  }

  @Test("A single file measures as itself")
  func singleFile() throws {
    let root = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("only.bin")
    try Self.write(4_096, to: file)

    let usage = DiskUsage.measure(file)

    #expect(usage.files == 1)
    #expect(usage.bytes >= 4_096)
    #expect(usage == DiskUsage.measure(root))
  }

  @Test("The counting predicate narrows the file count but not the bytes")
  func countingPredicate() throws {
    let root = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try Self.write(1_000, to: root.appendingPathComponent("doc.pdf"))
    try Self.write(1_000, to: root.appendingPathComponent("doc.meta.json"))

    let all = DiskUsage.measure(root)
    let pdfs = DiskUsage.measure(root) { $0.pathExtension == "pdf" }

    #expect(pdfs.files == 1)
    #expect(pdfs.bytes == all.bytes)
  }

  @Test("Measuring a list sums its entries and skips the missing ones")
  func measureList() throws {
    let root = try Self.makeDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let a = root.appendingPathComponent("db.sqlite")
    let b = root.appendingPathComponent("db.sqlite-wal")
    try Self.write(2_000, to: a)
    try Self.write(3_000, to: b)

    let usage = DiskUsage.measure([a, b, root.appendingPathComponent("db.sqlite-shm")])

    #expect(usage == DiskUsage.measure(a) + DiskUsage.measure(b))
    #expect(usage.files == 2)
  }
}
