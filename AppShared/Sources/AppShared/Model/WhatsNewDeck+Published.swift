import Common
import Foundation
import os

extension DocumentationLinks {
  /// Written by `scripts/whats_new.py` from the release note's front matter.
  public static func whatsNew(for version: Version) -> URL {
    baseUrl.appending(path: "whats_new/\(version).json")
  }
}

extension WhatsNewDeck.Card {
  public var imageURL: URL? {
    image.flatMap { URL(string: $0, relativeTo: DocumentationLinks.releaseNotes)?.absoluteURL }
  }
}

extension WhatsNewDeck {
  public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  /// The deck published for `version`, or `nil` when there is none or it can't
  /// be loaded, so callers fall back to the release notes.
  public static func published(
    for version: Version,
    fetch: Fetch = { try await URLSession.shared.data(for: $0) }
  ) async -> WhatsNewDeck? {
    var request = URLRequest(url: DocumentationLinks.whatsNew(for: version))
    // Launch waits on this, so a slow site must not hold up the release notes.
    request.timeoutInterval = 5

    do {
      let (data, response) = try await fetch(request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        return nil
      }
      let deck = try WhatsNewDeck(json: data)
      guard deck.version == version.description else {
        Logger.shared.error(
          "What's New deck for \(version, privacy: .public) is for \(deck.version, privacy: .public)"
        )
        return nil
      }
      return deck
    } catch {
      Logger.shared.error("Could not load What's New for \(version, privacy: .public): \(error)")
      return nil
    }
  }
}
