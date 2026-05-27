import Foundation

public struct ShareLink: Sendable, Equatable {
  // Wire-symmetric leaf enum; round-tripped as-is by the wire type and (future)
  // storage layer. Stays Codable per the Stage 3 principle.
  public enum FileVersion: String, Codable, Sendable {
    case original
    case archive
  }

  public var id: UInt
  public var created: Date
  public var expiration: Date?
  public var slug: String
  public var document: UInt
  public var fileVersion: FileVersion

  public init(
    id: UInt,
    created: Date,
    expiration: Date? = nil,
    slug: String,
    document: UInt,
    fileVersion: FileVersion
  ) {
    self.id = id
    self.created = created
    self.expiration = expiration
    self.slug = slug
    self.document = document
    self.fileVersion = fileVersion
  }
}

extension ShareLink: Model {}

public struct ProtoShareLink: Sendable {
  public var document: UInt
  public var expiration: Date?
  public var fileVersion: ShareLink.FileVersion

  public init(
    document: UInt,
    expiration: Date? = nil,
    fileVersion: ShareLink.FileVersion = .original
  ) {
    self.document = document
    self.expiration = expiration
    self.fileVersion = fileVersion
  }
}
