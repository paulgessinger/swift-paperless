//
//  DocumentChatResponse.swift
//  DataModel
//

import Foundation

/// A document the server's AI chat used to answer a question.
public struct DocumentChatReference: Sendable, Equatable, Hashable, Identifiable, Codable {
  public var id: UInt
  public var title: String

  public init(id: UInt, title: String) {
    self.id = id
    self.title = title
  }
}

/// The answer to a document chat question, as far as it has streamed in.
///
/// paperless-ngx streams the answer as plain text and, once it is done,
/// appends a metadata trailer (`\n\n__PAPERLESS_CHAT_METADATA__` followed by
/// `{"references": [...]}`) naming the documents it drew on. Older backends
/// send no trailer.
public struct DocumentChatResponse: Sendable, Equatable {
  public var content: String
  public var references: [DocumentChatReference]

  public init(content: String = "", references: [DocumentChatReference] = []) {
    self.content = content
    self.references = references
  }

  public static let metadataDelimiter = "\n\n__PAPERLESS_CHAT_METADATA__"

  private struct Metadata: Decodable {
    var references: [DocumentChatReference]?
  }

  /// Parses the raw text received so far, splitting off the metadata trailer.
  ///
  /// While only a prefix of the delimiter has arrived, that prefix is held back
  /// from `content`, so the marker never flashes up in the answer.
  public init(parsing raw: String) {
    if let range = raw.range(of: Self.metadataDelimiter) {
      content = String(raw[..<range.lowerBound])
      let trailer = Data(raw[range.upperBound...].utf8)
      references = (try? JSONDecoder().decode(Metadata.self, from: trailer))?.references ?? []
      return
    }

    references = []
    let delimiter = Self.metadataDelimiter
    for length in stride(from: min(delimiter.count, raw.count), to: 0, by: -1)
    where raw.hasSuffix(delimiter.prefix(length)) {
      content = String(raw.dropLast(length))
      return
    }
    content = raw
  }
}
