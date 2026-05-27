//
//  ApiRemoteVersion.swift
//  Networking
//

import Common
import DataModel
import MetaCodable

@Codable
@CodingKeys(.snake_case)
struct ApiRemoteVersion: Sendable {
  var version: String
  var updateAvailable: Bool
}

extension ApiRemoteVersion {
  var domain: RemoteVersion {
    // paperless-ngx returns "v<semver>" but older builds returned bare semver;
    // accept both.
    let parsed: Version?
    if version.hasPrefix("v") {
      parsed = Version(String(version.dropFirst()))
    } else {
      parsed = Version(version)
    }
    return RemoteVersion(version: parsed, updateAvailable: updateAvailable)
  }
}
