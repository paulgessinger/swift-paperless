//
//  MetadataModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

public struct Metadata: Sendable {
  public var originalChecksum: String
  public var originalSize: Int64
  public var originalMimeType: String
  public var mediaFilename: String
  public var hasArchiveVersion: Bool

  // Wire-symmetric value type — round-tripped by `ApiMetadata` and storage
  // alike. Stays `Codable` per the Stage 3 principle.
  public struct Item: Codable, Sendable, Equatable {
    public var namespace: String
    public var prefix: String
    public var key: String
    public var value: String

    public init(namespace: String, prefix: String, key: String, value: String) {
      self.namespace = namespace
      self.prefix = prefix
      self.key = key
      self.value = value
    }
  }

  public var originalMetadata: [Item]

  public var archiveChecksum: String?
  public var archiveMediaFilename: String?
  public var originalFilename: String
  public var archiveSize: Int64?

  public var archiveMetadata: [Item]?

  public var lang: String

  public init(
    originalChecksum: String,
    originalSize: Int64,
    originalMimeType: String,
    mediaFilename: String,
    hasArchiveVersion: Bool,
    originalMetadata: [Item],
    archiveChecksum: String? = nil,
    archiveMediaFilename: String? = nil,
    originalFilename: String,
    archiveSize: Int64? = nil,
    archiveMetadata: [Item]? = nil,
    lang: String
  ) {
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
}
