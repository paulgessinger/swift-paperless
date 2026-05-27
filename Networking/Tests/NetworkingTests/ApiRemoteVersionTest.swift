//
//  ApiRemoteVersionTest.swift
//  Networking
//

import Common
import DataModel
import Foundation
import Testing

@testable import Networking

@Test("Remote version can be decoded from JSON")
func testDecodeRemoteVersion() throws {
  let json = """
    {"version":"v2.20.5","update_available":true}
    """.data(using: .utf8)!

  let decoder = JSONDecoder()
  let remoteVersion = try decoder.decode(ApiRemoteVersion.self, from: json).domain

  #expect(remoteVersion.version == Version(2, 20, 5))
  #expect(remoteVersion.updateAvailable == true)
}

@Test("Remote version accepts bare semver without leading v")
func testDecodeRemoteVersionBareSemver() throws {
  let json = """
    {"version":"2.20.5","update_available":false}
    """.data(using: .utf8)!

  let decoder = JSONDecoder()
  let remoteVersion = try decoder.decode(ApiRemoteVersion.self, from: json).domain

  #expect(remoteVersion.version == Version(2, 20, 5))
  #expect(remoteVersion.updateAvailable == false)
}
