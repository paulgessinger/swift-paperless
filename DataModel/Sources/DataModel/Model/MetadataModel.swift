//
//  MetadataModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct Metadata: Sendable {
    public var originalChecksum: String
    public var originalSize: Int64
    public var originalMimeType: String
    public var mediaFilename: String
    public var hasArchiveVersion: Bool

    public struct Item: Codable, Sendable {
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
}
