import Foundation
import Testing

@testable import AppShared

@Suite
struct WhatsNewDeckTests {
  private func deck(blocks: String) throws -> WhatsNewDeck {
    let json = """
      {"version": "1.11.0", "pages": [{"title": "Page", "blocks": [\(blocks)]}]}
      """
    return try WhatsNewDeck(json: Data(json.utf8))
  }

  private let card = """
    "icon": "tag", "title": "Title", "text": "Text"
    """

  @Test func decodesEveryBlockType() throws {
    let result = try deck(
      blocks: """
        {"type": "card", \(card), "tint": "blue", "detail": "More"},
        {"type": "tip", \(card)},
        {"type": "telemetry", \(card)}
        """)

    let blocks = try #require(result.pages.first).blocks
    #expect(blocks.count == 3)

    guard case .card(let first) = blocks[0] else {
      Issue.record("Expected a card")
      return
    }
    #expect(first.tint == "blue")
    #expect(first.detail == "More")

    guard case .tip = blocks[1], case .telemetry = blocks[2] else {
      Issue.record("Expected tip and telemetry blocks")
      return
    }
  }

  @Test func skipsUnknownBlockTypes() throws {
    let result = try deck(
      blocks: """
        {"type": "from_the_future", "payload": 1},
        {"type": "card", \(card)}
        """)

    #expect(try #require(result.pages.first).blocks.count == 1)
  }

  @Test func subtitleIsOptional() throws {
    #expect(try #require(deck(blocks: "").pages.first).subtitle == nil)
  }

  @Test func rejectsCardWithoutRequiredFields() {
    #expect(throws: DecodingError.self) {
      try deck(blocks: #"{"type": "card", "icon": "tag"}"#)
    }
  }
}

@Suite
struct TipJarLinkTests {
  @Test(arguments: [
    "https://swift-paperless.app/tip",
    "https://swift-paperless.app/tip/",
    "https://swift-paperless.app/tip?source=release-notes",
  ])
  func matchesTipLink(_ value: String) throws {
    #expect(TipJarLink.matches(try #require(URL(string: value))))
  }

  @Test(arguments: [
    "https://swift-paperless.app/",
    "https://swift-paperless.app/tips",
    "https://swift-paperless.app/release_notes/tip",
    "http://swift-paperless.app/tip",
    "https://example.com/tip",
  ])
  func ignoresOtherLinks(_ value: String) throws {
    #expect(!TipJarLink.matches(try #require(URL(string: value))))
  }
}
