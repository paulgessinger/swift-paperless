//
//  Metadata.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

import Foundation

struct Metadata: Decodable {
    var originalChecksum: String
    var originalSize: Int64
    var originalMimeType: String
    var mediaFilename: String
    var hasArchiveVersion: Bool

    struct Item: Decodable {
        var namespace: String
        var prefix: String
        var key: String
        var value: String
    }

    var originalMetadata: [Item]

    var archiveChecksum: String?
    var archiveMediaFilename: String?
    var originalFilename: String
    var archiveSize: Int64?

    var archiveMetadata: [Item]?

    var lang: String

    private enum CodingKeys: String, CodingKey {
        case originalChecksum = "original_checksum"
        case originalSize = "original_size"
        case originalMimeType = "original_mime_type"
        case mediaFilename = "media_filename"
        case hasArchiveVersion = "has_archive_version"
        case originalMetadata = "original_metadata"
        case archiveChecksum = "archive_checksum"
        case archiveSize = "archive_size"
        case archiveMediaFilename = "archive_media_filename"
        case originalFilename = "original_filename"
        case archiveMetadata = "archive_metadata"
        case lang
    }
}
