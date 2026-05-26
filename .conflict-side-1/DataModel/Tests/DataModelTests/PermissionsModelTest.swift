import Foundation
import Testing

@testable import DataModel

@Suite
struct PermissionsModelTest {
  struct Object: Codable {
    var owner: Owner
  }

  struct Decoded: Decodable {
    let owner: UInt?
  }

  @Test func testOwnerEncodingUser() throws {
    let owner = Owner.user(1)
    let object = Object(owner: owner)

    let data = try JSONEncoder().encode(object)

    let decoded = try JSONDecoder().decode(Decoded.self, from: data)

    #expect(decoded.owner == 1)
  }

  @Test func testOwnerEncodingNone() throws {
    let owner = Owner.none
    let object = Object(owner: owner)
    let data = try JSONEncoder().encode(object)
    let decoded = try JSONDecoder().decode(Decoded.self, from: data)
    #expect(decoded.owner == nil)
  }

  @Test func testOwnerEncodingUnset() throws {
    let owner = Owner.unset
    let object = Object(owner: owner)
    let data = try JSONEncoder().encode(object)
    let decoded = try JSONDecoder().decode(Decoded.self, from: data)
    #expect(decoded.owner == nil)
  }

  @Test func testOwnerDecodingUser() throws {
    let data = try JSONEncoder().encode(Object(owner: .user(1)))
    let decoded = try JSONDecoder().decode(Object.self, from: data)
    #expect(decoded.owner == .user(1))
  }

  @Test func testOwnerDecodingNone() throws {
    let data = try JSONEncoder().encode(Object(owner: .none))
    let decoded = try JSONDecoder().decode(Object.self, from: data)
    #expect(decoded.owner == .none)
  }

  @Test("Test equality")
  func testEquality() throws {
    #expect(Owner.user(1) == Owner.user(1))
    #expect(Owner.user(1) != Owner.user(2))
    #expect(Owner.none == Owner.none)
    #expect(Owner.unset == Owner.unset)
    #expect(Owner.user(1) != Owner.none)
    #expect(Owner.user(1) != Owner.unset)
    #expect(Owner.none != Owner.unset)
  }
}
