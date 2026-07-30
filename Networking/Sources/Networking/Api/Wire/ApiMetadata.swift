//
//  ApiMetadata.swift
//  Networking
//

import DataModel

struct ApiMetadata: Decodable, Sendable {
  var original_checksum: String
  var original_size: Int64
  var original_mime_type: String
  var media_filename: String
  var has_archive_version: Bool
  var original_metadata: [Metadata.Item]
  var archive_checksum: String?
  var archive_media_filename: String?
  var original_filename: String
  var archive_size: Int64?
  var archive_metadata: [Metadata.Item]?
  var lang: String
}

extension ApiMetadata {
  var domain: Metadata {
    Metadata(
      originalChecksum: original_checksum,
      originalSize: original_size,
      originalMimeType: original_mime_type,
      mediaFilename: media_filename,
      hasArchiveVersion: has_archive_version,
      originalMetadata: original_metadata,
      archiveChecksum: archive_checksum,
      archiveMediaFilename: archive_media_filename,
      originalFilename: original_filename,
      archiveSize: archive_size,
      archiveMetadata: archive_metadata,
      lang: lang
    )
  }
}
