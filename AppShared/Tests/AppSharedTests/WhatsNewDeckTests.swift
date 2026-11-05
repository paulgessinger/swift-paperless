import Common
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

  @Test func resolvesImagesAgainstTheReleaseNotes() throws {
    let result = try deck(
      blocks: """
        {"type": "card", \(card), "image": "../assets/app_icon.png"},
        {"type": "card", \(card), "image": "https://example.com/a.png"},
        {"type": "card", \(card)}
        """)

    let urls = try #require(result.pages.first).blocks.map { block in
      guard case .card(let card) = block else { return URL?.none }
      return card.imageURL()
    }
    #expect(
      urls == [
        URL(string: "https://swift-paperless.app/assets/app_icon.png"),
        URL(string: "https://example.com/a.png"),
        nil,
      ])
  }

  @Test func imageShadowDefaultsToOff() throws {
    let result = try deck(
      blocks: """
        {"type": "card", \(card), "image": "a.png", "image_shadow": true},
        {"type": "card", \(card), "image": "a.png"}
        """)

    let shadows = try #require(result.pages.first).blocks.map { block in
      guard case .card(let card) = block else { return Bool?.none }
      return card.imageShadow
    }
    #expect(shadows == [true, false])
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

@Suite
struct PublishedWhatsNewDeckTests {
  private let version = Version("1.11.0")!

  private func fetch(status: Int, body: String) -> WhatsNewDeck.Fetch {
    { request in
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      return (Data(body.utf8), response)
    }
  }

  @Test
  func requestsTheVersionsFile() {
    #expect(
      DocumentationLinks.whatsNew(for: version).absoluteString
        == "https://swift-paperless.app/whats_new/1.11.0.json")
  }

  @Test
  func loadsAMatchingDeck() async {
    let body = #"{"version": "1.11.0", "pages": [{"title": "Page", "blocks": []}]}"#
    let deck = await WhatsNewDeck.published(for: version, fetch: fetch(status: 200, body: body))
    #expect(deck?.pages.first?.title == "Page")
  }

  @Test(arguments: [
    (404, "Not found"),
    (200, #"{"version": "1.10.0", "pages": []}"#),
    (200, "not json"),
  ])
  func fallsBackWithoutAUsableDeck(status: Int, body: String) async {
    #expect(
      await WhatsNewDeck.published(for: version, fetch: fetch(status: status, body: body)) == nil)
  }

  @Test
  func fallsBackWhenOffline() async {
    let deck = await WhatsNewDeck.published(for: version) { _ in
      throw URLError(.notConnectedToInternet)
    }
    #expect(deck == nil)
  }
}
