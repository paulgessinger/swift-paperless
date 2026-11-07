import Common
import DataModel
import Foundation
import Networking
import Persistence
import Testing

@testable import AppShared

@Suite
struct ConnectionMappingTests {
  private static func stored(knownVersions: BackendVersions?) -> StoredConnection {
    StoredConnection(
      url: URL(string: "https://example.com/api/")!,
      extraHeaders: [],
      user: User(id: 1, isSuperUser: false, username: "a"),
      knownVersions: knownVersions)
  }

  @Test("known versions survive a round trip through the record")
  func knownVersionsRoundTrip() {
    let versions = BackendVersions(apiVersion: 9, backendVersion: Version(2, 18, 4))
    let record = Self.stored(knownVersions: versions).toRecord(needsAuth: false)
    #expect(record.apiVersion == 9)
    #expect(record.backendVersion == "2.18.4")
    #expect(StoredConnection(record: record).knownVersions == versions)
  }

  @Test("an unseeded server maps to empty columns and back")
  func unseededRoundTrip() {
    let record = Self.stored(knownVersions: nil).toRecord(needsAuth: false)
    #expect(record.apiVersion == nil)
    #expect(record.backendVersion == nil)
    #expect(StoredConnection(record: record).knownVersions == nil)
  }

  @Test("a half-known or unparseable pair does not seed")
  func partialVersionsDoNotSeed() {
    var record = Self.stored(knownVersions: nil).toRecord(needsAuth: false)
    record.apiVersion = 9
    #expect(StoredConnection(record: record).knownVersions == nil)
    record.backendVersion = "not-a-version"
    #expect(StoredConnection(record: record).knownVersions == nil)
  }

  @Test("an API version the column can't hold is not stored")
  func outOfRangeApiVersionIsNotStored() {
    let versions = BackendVersions(apiVersion: .max, backendVersion: Version(2, 18, 4))
    let record = Self.stored(knownVersions: versions).toRecord(needsAuth: false)
    #expect(record.apiVersion == nil)
    #expect(record.backendVersion == nil)
  }

  @Test("the sign-in method survives a round trip, and an unrecorded one stays nil")
  func authMethodRoundTrip() {
    for method in ConnectionAuthMethod.allCases {
      var stored = Self.stored(knownVersions: nil)
      stored.authMethod = method
      let record = stored.toRecord(needsAuth: false)
      #expect(record.authMethod == method.rawValue)
      #expect(StoredConnection(record: record).authMethod == method)
    }

    let unrecorded = Self.stored(knownVersions: nil).toRecord(needsAuth: false)
    #expect(unrecorded.authMethod == nil)
    #expect(StoredConnection(record: unrecorded).authMethod == nil)

    var unknown = unrecorded
    unknown.authMethod = "passkey"
    #expect(StoredConnection(record: unknown).authMethod == nil)
  }
}
