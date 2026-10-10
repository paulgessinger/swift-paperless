import Common
import DataModel
import Foundation

@testable import Persistence

/// What the file index and content reclaim suites share: documents, servers,
/// keys and a store in a temporary directory.
enum FileFixtures {
  static func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

  static func doc(_ id: UInt, modified: Date? = nil) -> Document {
    Document(
      id: id, title: "d\(id)", created: date(1000), tags: [], modified: modified, owner: .user(1))
  }

  static func versioned(_ id: UInt, versions: [UInt]) -> Document {
    Document(
      id: id, title: "v", created: date(1000), tags: [], owner: .user(1),
      versions: versions.map {
        DocumentVersion(id: $0, added: date(1000), isRoot: $0 == versions.first)
      })
  }

  static func addServer(_ id: UUID, to database: Database) throws {
    try database.upsertConnection(
      ConnectionRecord(
        id: id,
        url: URL(string: "https://\(id.uuidString).example.com/api/")!,
        user: .init(id: 1, isSuperUser: true, username: "other")))
  }

  static func key(_ server: UUID, _ version: UInt, _ kind: ContentStore.Kind = .archive)
    -> ContentStore.Key
  {
    ContentStore.Key(serverID: server, versionID: version, kind: kind)
  }

  static func makeStore() throws -> ContentStore {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("FileFixtures-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return try ContentStore(root: root)
  }

  /// A row for an archive accessed at `accessed`, with no file behind it.
  static func record(
    _ database: Database, _ key: ContentStore.Key, size: Int64, accessed: Date
  ) async throws {
    try await database.recordFile(
      key, documentID: key.versionID, size: size, modified: nil, checksum: nil,
      storedAt: accessed, lastAccessedAt: accessed)
  }
}

extension Database {
  /// The row for `key` whatever it was fetched against.
  func anyFile(_ key: ContentStore.Key) async throws -> FileRecord? {
    try await writer.read { db in try FileRecord.fetchAll(db) }.first { $0.key == key }
  }
}
