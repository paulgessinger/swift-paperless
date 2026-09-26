import Common
import Foundation
import Testing

@testable import Persistence

@Suite("Database disk usage")
struct DatabaseDiskUsageTests {
  @Test("An in-memory database has no file and measures as zero")
  func inMemory() throws {
    let database = try Persistence.Database.inMemory()
    #expect(database.fileURL == nil)
    #expect(database.diskUsage() == .zero)
  }

  @Test("An on-disk database counts its main file and its WAL sidecars")
  func onDisk() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DatabaseDiskUsageTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("test.sqlite")
    let database = try Persistence.Database(path: path)

    #expect(database.fileURL?.standardizedFileURL == path.standardizedFileURL)

    let wal = path.deletingPathExtension().appendingPathExtension("sqlite-wal")
    let shm = path.deletingPathExtension().appendingPathExtension("sqlite-shm")
    // Migrations ran through the pool, so WAL mode has created both sidecars.
    #expect(FileManager.default.fileExists(atPath: wal.path))
    #expect(FileManager.default.fileExists(atPath: shm.path))

    let usage = database.diskUsage()
    #expect(usage == DiskUsage.measure([path, wal, shm]))
    #expect(usage.files == 3)
    #expect(usage.bytes > DiskUsage.measure(path).bytes)
  }

  @Test(
    "Sidecars are found for a database whose name does not end in .sqlite",
    arguments: ["cache.db", "cache"])
  func sidecarsOfAnyFilename(name: String) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("DatabaseDiskUsageTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent(name)
    let database = try Persistence.Database(path: path)

    // SQLite appends its suffixes to the whole filename, whatever it is, so
    // these are the files that actually exist next to the database.
    let wal = directory.appendingPathComponent("\(name)-wal")
    let shm = directory.appendingPathComponent("\(name)-shm")
    #expect(FileManager.default.fileExists(atPath: wal.path))
    #expect(FileManager.default.fileExists(atPath: shm.path))

    let usage = database.diskUsage()
    #expect(usage == DiskUsage.measure([path, wal, shm]))
    // The regression: deriving the sidecars by swapping the extension looked
    // for `cache.sqlite-wal`, which does not exist, so only the main file was
    // counted and both sidecars silently measured as zero.
    #expect(usage.files == 3)
    #expect(usage.bytes > DiskUsage.measure(path).bytes)
  }
}
