import Foundation

/// A paged What's New presentation for one app version.
public struct WhatsNewDeck: Decodable, Equatable, Sendable {
  public struct Page: Decodable, Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let blocks: [Block]

    private enum CodingKeys: String, CodingKey {
      case title, subtitle, blocks
    }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      title = try container.decode(String.self, forKey: .title)
      subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
      blocks = try container.decode([LossyBlock].self, forKey: .blocks).compactMap(\.block)
    }
  }

  public struct Card: Decodable, Equatable, Sendable {
    /// SF Symbol name.
    public let icon: String
    public let tint: String?
    public let title: String
    public let text: String
    /// Markdown shown when the reader asks for more.
    public let detail: String?
  }

  public enum Block: Equatable, Sendable {
    case card(Card)
    case tip(Card)
    case telemetry(Card)
  }

  /// Decks are published independently of app builds, so a block type this
  /// build doesn't know has to be skipped rather than fail the whole deck.
  private struct LossyBlock: Decodable {
    let block: Block?

    private enum CodingKeys: String, CodingKey {
      case type
    }

    init(from decoder: any Decoder) throws {
      let type = try decoder.container(keyedBy: CodingKeys.self)
        .decode(String.self, forKey: .type)

      switch type {
      case "card": block = .card(try Card(from: decoder))
      case "tip": block = .tip(try Card(from: decoder))
      case "telemetry": block = .telemetry(try Card(from: decoder))
      default: block = nil
      }
    }
  }

  public let version: String
  public let pages: [Page]

  public init(json: Data) throws {
    self = try JSONDecoder().decode(Self.self, from: json)
  }
}
