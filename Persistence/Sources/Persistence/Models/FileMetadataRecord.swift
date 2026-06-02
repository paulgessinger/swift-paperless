import DataModel
import Foundation
import GRDB

/// GRDB record for a file version's cached `/metadata/` sub-resource
/// (`file_metadata` table, keyed `(server_id, version_id)`).
///
/// Immutable per file version, so a cached copy never goes stale until the
/// version changes — hence the version key rather than the document id. `Metadata`
/// isn't `Codable`, so the payload is an explicit storage mirror mapped by hand
/// (`Metadata.Item` is already a wire-symmetric `Codable` leaf and is reused).
public struct FileMetadataRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "file_metadata"

  public var serverId: UUID
  public var versionId: UInt
  public var payload: Payload

  public struct Payload: Codable, Sendable, Equatable {
    public var originalChecksum: String
    public var originalSize: Int64
    public var originalMimeType: String
    public var mediaFilename: String
    public var hasArchiveVersion: Bool
    public var originalMetadata: [Metadata.Item]
    public var archiveChecksum: String?
    public var archiveMediaFilename: String?
    public var originalFilename: String
    public var archiveSize: Int64?
    public var archiveMetadata: [Metadata.Item]?
    public var lang: String
  }

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case versionId = "version_id"
    case payload = "data"
  }

  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }
}

extension FileMetadataRecord {
  public init(serverId: UUID, versionId: UInt, domain: Metadata) {
    self.serverId = serverId
    self.versionId = versionId
    payload = Payload(
      originalChecksum: domain.originalChecksum,
      originalSize: domain.originalSize,
      originalMimeType: domain.originalMimeType,
      mediaFilename: domain.mediaFilename,
      hasArchiveVersion: domain.hasArchiveVersion,
      originalMetadata: domain.originalMetadata,
      archiveChecksum: domain.archiveChecksum,
      archiveMediaFilename: domain.archiveMediaFilename,
      originalFilename: domain.originalFilename,
      archiveSize: domain.archiveSize,
      archiveMetadata: domain.archiveMetadata,
      lang: domain.lang)
  }

  public var domain: Metadata {
    Metadata(
      originalChecksum: payload.originalChecksum,
      originalSize: payload.originalSize,
      originalMimeType: payload.originalMimeType,
      mediaFilename: payload.mediaFilename,
      hasArchiveVersion: payload.hasArchiveVersion,
      originalMetadata: payload.originalMetadata,
      archiveChecksum: payload.archiveChecksum,
      archiveMediaFilename: payload.archiveMediaFilename,
      originalFilename: payload.originalFilename,
      archiveSize: payload.archiveSize,
      archiveMetadata: payload.archiveMetadata,
      lang: payload.lang)
  }
}
