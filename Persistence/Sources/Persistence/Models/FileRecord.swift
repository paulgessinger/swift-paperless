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

  /// The kinds the file pass keeps on the device: a document's archive and
  /// its text, for a server in *Entire library* or a document kept offline.
  static let pinnableKinds = [ContentStore.Kind.archive, .content].map(\.rawValue)

  /// The rows a storage budget may evict, least recently accessed first: the
  /// pool's kinds, except its pinned kinds for a server in *Entire library*
  /// and for a document kept offline, and except the texts of a server that
  /// keeps its library's text. The one definition of "evictable".
  static func evictable(_ pool: EvictionPool) -> QueryInterfaceRequest<FileRecord> {
    let file = TableAlias()
    let libraryServer =
      ConnectionRecord
      .filter(Column("id") == file[Column("server_id")])
      .filter(ConnectionRecord.Columns.offlineBrowsingMode == "entireLibrary")
    let kept = KeptOfflineRecord.keeping(
      server: file[Column("server_id")], document: file[Column("document_id")])
    // A server that keeps its library's text keeps every text, and only the
    // texts: its archives stay evictable.
    let textServer =
      ConnectionRecord
      .filter(Column("id") == file[Column("server_id")])
      .filter(ConnectionRecord.Columns.libraryText == true)
    return aliased(file)
      .filter(pool.kinds.contains(Column("kind")))
      .filter(
        !(pool.pinnedKinds.contains(Column("kind"))
          && (libraryServer.exists() || kept.exists()))
      )
      .filter(!(Column("kind") == ContentStore.Kind.content.rawValue && textServer.exists()))
  }
}

/// A set of file kinds held against one storage budget.
public enum EvictionPool: Sendable, CaseIterable {
  /// Originals, archives and texts, against `StoragePolicy.documentBudgetBytes`.
  case documents
  /// Thumbnails, against `StoragePolicy.thumbnailBudgetBytes`.
  case thumbnails

  /// The pool a file of `kind` is held in.
  public init(kind: ContentStore.Kind) {
    switch kind {
    case .original, .archive, .content: self = .documents
    case .thumbnail: self = .thumbnails
    }
  }

  var kinds: [String] {
    switch self {
    case .documents: [ContentStore.Kind.original, .archive, .content].map(\.rawValue)
    case .thumbnails: [ContentStore.Kind.thumbnail.rawValue]
    }
  }

  /// The kinds an *Entire library* server or a kept document exempts.
  var pinnedKinds: [String] {
    switch self {
    case .documents: FileRecord.pinnableKinds
    case .thumbnails: [ContentStore.Kind.thumbnail.rawValue]
    }
  }
}
