//
//  ApiMetadata.swift
//  Networking
//

import DataModel
import MetaCodable

@Codable
@CodingKeys(.snake_case)
struct ApiMetadata: Sendable {
  var originalChecksum: String
  var originalSize: Int64
  var originalMimeType: String
  var mediaFilename: String
  var hasArchiveVersion: Bool
  var originalMetadata: [Metadata.Item]
  var archiveChecksum: String?
  var archiveMediaFilename: String?
  var originalFilename: String
  var archiveSize: Int64?
  var archiveMetadata: [Metadata.Item]?
  var lang: String
}

extension ApiMetadata {
  var domain: Metadata {
    Metadata(
      originalChecksum: originalChecksum,
      originalSize: originalSize,
      originalMimeType: originalMimeType,
      mediaFilename: mediaFilename,
      hasArchiveVersion: hasArchiveVersion,
      originalMetadata: originalMetadata,
      archiveChecksum: archiveChecksum,
      archiveMediaFilename: archiveMediaFilename,
      originalFilename: originalFilename,
      archiveSize: archiveSize,
      archiveMetadata: archiveMetadata,
      lang: lang
    )
  }
}
