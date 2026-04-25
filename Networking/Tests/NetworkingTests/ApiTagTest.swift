import Common
import DataModel
import Foundation
import SwiftUI
import Testing

@testable import Networking

private let decoder = makeDecoder(tz: .current)

@Suite
struct ApiTagTest {
  @Test func testDecoding() throws {
    let data = try #require(testData("Data/tags.json"))
    let tags = try decoder.decode([ApiTag].self, from: data).map(\.domain)

    #expect(tags[0].id == 66)
    #expect(tags[0].slug == "tech-dept")
    #expect(tags[0].name == "Tech Department")
    #expect(tags[0].color.color == Color(hex: "#bde38f")!)
    #expect(tags[0].match == "")
    #expect(tags[0].matchingAlgorithm == .auto)
    #expect(tags[0].isInsensitive == false)
    #expect(tags[0].isInboxTag == false)

    #expect(tags[1].id == 71)
    #expect(tags[1].slug == "project-alpha")
    #expect(tags[1].name == "Project Alpha")
    #expect(tags[1].color.color == Color(hex: "#ca6beb")!)
    #expect(tags[1].matchingAlgorithm == .any)

    #expect(tags[2].id == 131)
    #expect(tags[2].color.color == Color(hex: "#eb87e0")!)
    #expect(tags[2].isInsensitive == true)
    #expect(tags[2].name == "Finance 2023")
    #expect(tags[2].matchingAlgorithm == .auto)

    // Older backends do not emit `parent`/`children`; absence decodes as nil.
    #expect(tags.allSatisfy { $0.parent == nil })
  }

  @Test("Decodes nested parent/children from paperless-ngx v2.19.3+")
  func testDecodingNested() throws {
    let data = try #require(testData("Data/tags-v219.json"))
    let topLevel = try decoder.decode([ApiTag].self, from: data)
    #expect(topLevel.count == 7)

    let all = topLevel.flattenedUnique.map(\.domain)
    assertNestedTagsV219(all)
  }

  // paperless-ngx 2.19.0–2.19.2 returned nested tags both at the array root
  // and inside their parent's `children`. Flattening must dedupe by id.
  @Test("Deduplicates nested children also returned at root (2.19.0–2.19.2)")
  func testDecodingNestedDuplicated() throws {
    let data = try #require(testData("Data/tags-v219-duplicated.json"))
    let topLevel = try decoder.decode([ApiTag].self, from: data)
    #expect(topLevel.count == 10)

    let all = topLevel.flattenedUnique.map(\.domain)
    assertNestedTagsV219(all)
  }

  // The paperless-ngx update endpoint treats a missing `parent` key as
  // "unchanged", so clearing the parent must encode as explicit JSON `null`.
  @Test("ApiTagUpdate emits `parent: null` when cleared")
  func testEncodingClearsParent() throws {
    let update = ApiTagUpdate(
      id: 7,
      is_inbox_tag: false,
      name: "Tag",
      slug: "tag",
      color: HexColor(Color(hex: "#ff0000")!),
      match: "",
      matching_algorithm: .auto,
      is_insensitive: true,
      parent: nil
    )

    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update))
    let dict = try #require(json as? [String: Any])

    #expect(dict.keys.contains("parent"))
    #expect(dict["parent"] is NSNull)
  }

  @Test("ApiTagUpdate emits parent id when set")
  func testEncodingKeepsParent() throws {
    let update = ApiTagUpdate(
      id: 7,
      is_inbox_tag: false,
      name: "Tag",
      slug: "tag",
      color: HexColor(Color(hex: "#ff0000")!),
      match: "",
      matching_algorithm: .auto,
      is_insensitive: true,
      parent: 42
    )

    let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update))
    let dict = try #require(json as? [String: Any])

    #expect((dict["parent"] as? NSNumber)?.uintValue == 42)
  }
}

private func assertNestedTagsV219(_ all: [DataModel.Tag]) {
  #expect(all.count == 10)

  let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

  // Roots
  #expect(byId[14]?.parent == nil)
  #expect(byId[17]?.parent == nil)
  #expect(byId[1]?.parent == nil)

  // First-level children of tag 17
  #expect(byId[18]?.parent == 17)
  #expect(byId[18]?.name == "Child 1 level 1")
  #expect(byId[19]?.parent == 17)
  #expect(byId[19]?.name == "Child 2 level 1")

  // Second-level child of tag 18
  #expect(byId[20]?.parent == 18)
  #expect(byId[20]?.name == "Child 1 level 2")
  #expect(byId[20]?.color.color == Color(hex: "#97e5c8")!)
}
