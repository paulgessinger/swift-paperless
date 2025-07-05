//
//  VersionTests.swift
//  Common
//
//  Created by Paul Gessinger on 30.11.2024.
//

import Foundation
import Testing

@testable import Common

@Suite
struct VersionTests {
  @Test
  func constructFromString() {
    #expect(Version("1.0.0") == .init(major: 1, minor: 0, patch: 0))
    #expect(Version("1.0.1") == .init(major: 1, minor: 0, patch: 1))
    #expect(Version("1.") == nil)
    #expect(Version("1.0") == nil)
    #expect(Version(".0.1.2") == nil)
    #expect(Version(".1.2") == nil)
  }

  @Test
  func convertToString() {
    #expect("\(Version(1, 2, 3))" == "1.2.3")

    #expect(String(describing: Version(4, 5, 6)) == "4.5.6")
  }

  @Test
  func access() {
    let version = Version(1, 2, 3)
    #expect(version.major == 1)
    #expect(version.minor == 2)
    #expect(version.patch == 3)

    let version2 = Version(major: 1, minor: 2, patch: 3)
    #expect(version2.major == 1)
    #expect(version2.minor == 2)
    #expect(version2.patch == 3)
  }

  @Test
  func comparable() {
    #expect(Version(0, 0, 1) < Version(0, 0, 2))
    #expect(Version(0, 1, 0) < Version(0, 9, 0))
    #expect(Version(1, 0, 0) < Version(2, 0, 0))

    #expect(Version(0, 0, 1) <= Version(0, 0, 2))
    #expect(Version(0, 1, 0) >= Version(0, 0, 9))
    #expect(Version(1, 0, 0) >= Version(0, 9, 9))

    #expect(Version(0, 0, 2) > Version(0, 0, 1))
    #expect(Version(0, 0, 9) < Version(0, 1, 0))
    #expect(Version(0, 9, 9) < Version(1, 0, 0))

    #expect(Version(0, 0, 2) >= Version(0, 0, 1))

    #expect(Version(1, 0, 0) <= Version(1, 0, 0))
    #expect(Version(1, 0, 0) >= Version(1, 0, 0))
  }

  @Test
  func appVersionCoding() throws {
    let version = Version(1, 2, 3)
    let appVersion = AppVersion(version: version, build: 42)

    let encoder = JSONEncoder()
    let data = try encoder.encode(appVersion)

    // Parse and compare the actual values instead of raw JSON
    let jsonObject = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(jsonObject["release"] as! [Int] == [1, 2, 3])
    #expect(jsonObject["build"] as! Int == 42)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(AppVersion.self, from: data)

    #expect(decoded.version == version)
    #expect(decoded.build == 42)
  }

  @Test
  func appVersionInitializers() {
    let version = Version(1, 2, 3)
    let appVersion1 = AppVersion(version: version, build: 42)
    #expect(appVersion1.version == version)
    #expect(appVersion1.build == 42)

    let appVersion2 = AppVersion(version: "1.2.3", build: "42")
    #expect(appVersion2?.version == version)
    #expect(appVersion2?.build == 42)

    #expect(AppVersion(version: "1.2", build: "42") == nil)
    #expect(AppVersion(version: "1.2.3.4", build: "42") == nil)
    #expect(AppVersion(version: "a.b.c", build: "42") == nil)
    #expect(AppVersion(version: "1.2.3", build: "abc") == nil)
    #expect(AppVersion(version: "1.2.3", build: "-42") == nil)

    let appVersion3 = AppVersion(version: "1.2.3", build: "42")
    #expect(appVersion3?.version == version)
    #expect(appVersion3?.build == 42)
  }

  @Test
  func appVersionInvalidDecoding() throws {
    let invalidJson = #"{"release":[1,2],"build":42}"#.data(using: .utf8)!
    let decoder = JSONDecoder()

    #expect(throws: DecodingError.self) {
      try decoder.decode(AppVersion.self, from: invalidJson)
    }
  }
}
