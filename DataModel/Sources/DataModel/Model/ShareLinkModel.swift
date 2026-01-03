import Common
import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ShareLink : Sendable {
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
}

extension ShareLink : Model {}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ProtoShareLink: Sendable {
  public var expiration: Date?
  public var document: UInt
  public var fileVersion: ShareLink.FileVersion
}
