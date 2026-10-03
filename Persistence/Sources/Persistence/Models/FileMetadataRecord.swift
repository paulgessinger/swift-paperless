import DataModel
import Foundation
import GRDB

/// GRDB record for a file version's cached `/metadata/` sub-resource
/// (`file_metadata` table, keyed `(server_id, version_id)`).
///
/// Keyed by version because checksums, sizes and embedded metadata are fixed per
/// file version. The filenames are not: moving the file changes them under the
/// same version, so `documentModified` records which document state the row was
/// fetched under. `Metadata` isn't `Codable`, so the payload is an explicit
/// storage mirror mapped by hand (`Metadata.Item` is already a wire-symmetric
/// `Codable` leaf and is reused).
public struct FileMetadataRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  public static let databaseTableName = "file_metadata"

  public var serverId: UUID
  public var versionId: UInt
  /// The document's `modified` when this was fetched, or `nil` if unknown.
  /// Reference-date seconds, like `document.modified`.
  public var documentModified: Date?
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
    case documentModified = "document_modified"
    case payload = "data"
  }

  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }

  public static func databaseDateEncodingStrategy(for column: String)
    -> DatabaseDateEncodingStrategy
  {
    .timeIntervalSinceReferenceDate
  }

  public static func databaseDateDecodingStrategy(for column: String)
    -> DatabaseDateDecodingStrategy
  {
    .timeIntervalSinceReferenceDate
  }
}

extension FileMetadataRecord {
  public init(serverId: UUID, versionId: UInt, documentModified: Date?, domain: Metadata) {
    self.serverId = serverId
    self.versionId = versionId
    self.documentModified = documentModified
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
