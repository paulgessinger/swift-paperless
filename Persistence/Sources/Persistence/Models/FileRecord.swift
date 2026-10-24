import Common
import Foundation
import GRDB

/// GRDB record for a row in the `file` table: one cached blob in the
/// `ContentStore`, keyed like the store.
///
/// `kind` is the raw `ContentStore.Kind`. Timestamps are
/// `timeIntervalSinceReferenceDate` (REAL).
public struct FileRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "file"

  public var serverId: UUID
  public var versionId: UInt
  public var kind: String
  public var documentId: UInt
  public var size: Int64
  public var modified: Double?
  public var checksum: String?
  public var storedAt: Double
  public var lastAccessedAt: Double?

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case versionId = "version_id"
    case kind
    case documentId = "document_id"
    case size
    case modified
    case checksum
    case storedAt = "stored_at"
    case lastAccessedAt = "last_accessed_at"
  }

  /// The store key this row describes; `nil` for a kind this build doesn't know.
  public var key: ContentStore.Key? {
    ContentStore.Kind(rawValue: kind).map {
      ContentStore.Key(serverID: serverId, versionID: versionId, kind: $0)
    }
  }

  /// The kinds the storage budget may evict. Thumbnails live and die with
  /// their document row instead.
  static let evictableKinds = [ContentStore.Kind.original, .archive].map(\.rawValue)

  /// The rows the storage budget may evict: evictable kinds, except the
  /// archives the file pass keeps on the device, those of a server in *Entire
  /// library* and those of a document kept offline. The one definition of
  /// "evictable".
  static var evictable: QueryInterfaceRequest<FileRecord> {
    let file = TableAlias()
    let libraryServer =
      ConnectionRecord
      .filter(Column("id") == file[Column("server_id")])
      .filter(ConnectionRecord.Columns.offlineBrowsingMode == "entireLibrary")
    let kept = KeptOfflineRecord.isKept(
      server: file[Column("server_id")], document: file[Column("document_id")])
    return aliased(file)
      .filter(evictableKinds.contains(Column("kind")))
      .filter(
        !(Column("kind") == ContentStore.Kind.archive.rawValue
          && (libraryServer.exists() || kept)))
  }
}
