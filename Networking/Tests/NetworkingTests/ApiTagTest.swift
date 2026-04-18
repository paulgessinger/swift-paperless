import Common
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
  }
}
