//
//  RemoteVersionModel.swift
//  DataModel
//
//  Created by Paul Gessinger on 24.01.26.
//

import Common
import MetaCodable

@Codable
@CodingKeys(.snake_case)
public struct RemoteVersion {
  @CodedAs("version")
  private let versionImpl: String

  public let updateAvailable: Bool

  public init(version: Version, updateAvailable: Bool) {
    self.versionImpl = "v\(version)"
    self.updateAvailable = updateAvailable
  }

  public var version: Version? {
    if versionImpl.hasPrefix("v") {
      return Version(String(versionImpl.dropFirst()))
    } else {
      return Version(versionImpl)
    }
  }
}
