//
//  PageCursor.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.26.
//

import DataModel
import Foundation
import os

// Page-oriented cursor over a Paperless `ListResponse<Element>` endpoint.
//
// Each `nextPage()` call issues one
// HTTP request and returns the full server page along with the cumulative
// pagination signals (`isExhausted`, `totalCount`). The cursor flips
// `isExhausted` as soon as the server says `next == nil`, so callers do not pay
// a wasted final round-trip just to discover the list ended.
public actor PageCursor<Element: Decodable & Sendable> {
  public struct Page: Sendable {
    public let items: [Element]
    public let totalCount: UInt
    public let isLast: Bool
  }

  // Injected by tests: the cursor only needs to fetch a `ListResponse<Element>`
  // for a URL and to apply the connection-scheme fix to next-page URLs.
  // Production builds compose these from `ApiRepository`.
  public typealias Fetch = @Sendable (URL) async throws -> ListResponse<Element>
  public typealias FixURL = @Sendable (URL) -> URL

  public private(set) var totalCount: UInt?
  public private(set) var isExhausted: Bool = false

  private var nextURL: URL?
  private let fetch: Fetch
  private let fixURL: FixURL

  public init(initialURL: URL, fetch: @escaping Fetch, fixURL: @escaping FixURL = { $0 }) {
    nextURL = initialURL
    self.fetch = fetch
    self.fixURL = fixURL
  }

  // Returns the next page from the server, or nil if the cursor is already
  // exhausted (no request is issued in that case). Throws CancellationError
  // when the surrounding task is cancelled — never silently returns nil for
  // cancellation.
  public func nextPage() async throws -> Page? {
    if isExhausted { return nil }
    guard let url = nextURL else {
      isExhausted = true
      return nil
    }

    try Task.checkCancellation()

    do {
      let decoded = try await fetch(url)

      totalCount = decoded.count

      let isLast = decoded.next == nil
      if let next = decoded.next {
        nextURL = fixURL(next)
      } else {
        nextURL = nil
        isExhausted = true
      }

      return Page(items: decoded.results, totalCount: decoded.count, isLast: isLast)

    } catch let RequestError.forbidden(details) {
      Logger.networking.error("Error in \(Element.self, privacy: .public) PageCursor: Forbidden")
      throw ResourceForbidden(Element.self, response: details)
    } catch let error where error.isCancellationError {
      Logger.networking.info("\(Element.self, privacy: .public) PageCursor was cancelled")
      throw error
    } catch {
      Logger.networking.error(
        "Error in \(Element.self, privacy: .public) PageCursor: \(String(describing: error), privacy: .public)"
      )
      throw error
    }
  }

  // Drains the cursor and returns every item across all pages.
  public func collectAll() async throws -> [Element] {
    var all: [Element] = []
    while let page = try await nextPage() {
      all.append(contentsOf: page.items)
    }
    return all
  }
}

extension PageCursor {
  // Convenience initializer for production callers that already hold an
  // `ApiRepository`. Wires `fetch` to `repository.fetchData(for:as:)` and
  // `fixURL` to the connection-scheme replacement helper.
  public init(repository: ApiRepository, initialURL: URL) {
    let scheme = repository.connection.scheme
    self.init(
      initialURL: initialURL,
      fetch: { url in
        let request = await repository.request(url: url)
        return try await repository.fetchData(for: request, as: ListResponse<Element>.self)
      },
      fixURL: { url in
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
          Logger.networking.error(
            "Unable to decompose next-page URL for cursor URL fix, continuing with original URL")
          return url
        }
        components.scheme = scheme
        guard let result = components.url else {
          Logger.networking.error(
            "Could not reassemble URL after cursor URL fix, continuing with original URL")
          return url
        }
        return result
      }
    )
  }
}
