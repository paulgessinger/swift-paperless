//
//  Metadata.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

import Foundation

public struct Metadata: Decodable, Sendable {
    public var originalChecksum: String
    public var originalSize: Int64
    public var originalMimeType: String
    public var mediaFilename: String
    public var hasArchiveVersion: Bool

    public struct Item: Decodable, Sendable {
        public var namespace: String
        public var prefix: String
        public var key: String
        public var value: String
    }

    public var originalMetadata: [Item]

    public var archiveChecksum: String?
    public var archiveMediaFilename: String?
    public var originalFilename: String
    public var archiveSize: Int64?

    public var archiveMetadata: [Item]?

    public var lang: String

    public init(originalChecksum: String, originalSize: Int64, originalMimeType: String, mediaFilename: String, hasArchiveVersion: Bool, originalMetadata: [Item], archiveChecksum: String? = nil, archiveMediaFilename: String? = nil, originalFilename: String, archiveSize: Int64? = nil, archiveMetadata: [Item]? = nil, lang: String) {
        self.originalChecksum = originalChecksum
        self.originalSize = originalSize
        self.originalMimeType = originalMimeType
        self.mediaFilename = mediaFilename
        self.hasArchiveVersion = hasArchiveVersion
        self.originalMetadata = originalMetadata
        self.archiveChecksum = archiveChecksum
        self.archiveMediaFilename = archiveMediaFilename
        self.originalFilename = originalFilename
        self.archiveSize = archiveSize
        self.archiveMetadata = archiveMetadata
        self.lang = lang
    }

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
