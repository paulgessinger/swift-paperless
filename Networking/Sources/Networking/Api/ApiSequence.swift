//
//  ApiSequence.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.05.2024.
//

import DataModel
import Foundation
import os
import Semaphore

public actor ApiSequence<Element>: AsyncSequence, AsyncIteratorProtocol
    where Element: Model & Decodable & Sendable
{
    private var nextPage: URL?
    private let repository: ApiRepository

    private var buffer: [Element]?
    private var bufferIndex = 0

    private(set) var hasMore = true

    private let semaphore = AsyncSemaphore(value: 1)

    public init(repository: ApiRepository, url: URL) {
        self.repository = repository
        nextPage = url
    }

    private func fixUrl(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.networking.error("Unable to decompose next-page URL for sequence URL fix, continuing with original URL")
            return url
        }

        components.scheme = repository.connection.scheme

        guard let result = components.url else {
            Logger.networking.error("Could not reassemble URL after sequence URL fix, continuing with original URL")
            return url
        }

        return result
    }

    public func next() async throws -> Element? {
        await semaphore.wait()
        defer { semaphore.signal() }

        guard !Task.isCancelled else {
            Logger.networking.notice("API sequence (\(Element.self, privacy: .public) next task was cancelled.")
            return nil
        }

        // if we have a current page loaded, return next element from that
        if let buffer, bufferIndex < buffer.count {
            defer { bufferIndex += 1 }
            return buffer[bufferIndex]
        }

        guard let url = nextPage else {
            Logger.networking.notice("\(Element.self, privacy: .public) API sequence has reached end (nextPage is nil)")
            hasMore = false
            return nil
        }

        do {
            let request = await repository.request(url: url)
            let decoded = try await repository.fetchData(for: request, as: ListResponse<Element>.self)

            guard !decoded.results.isEmpty else {
                Logger.networking.notice("\(Element.self, privacy: .public) API sequence fetch was empty")
                hasMore = false
                return nil
            }

            // Workaround for https://github.com/paulgessinger/swift-paperless/issues/68
            Logger.networking.trace("Fixing URL to next page with configured backend scheme")

            nextPage = nil
            if let next = decoded.next {
                nextPage = fixUrl(next)
            }
            buffer = decoded.results
            bufferIndex = 1 // set to one because we return the first element immediately
            return decoded.results[0]

        } catch let RequestError.forbidden(details) {
            Logger.networking.error("Error in \(Element.self, privacy: .public) API sequence: Forbidden")
            throw ResourceForbidden(Element.self, response: details)
        } catch let error where error.isCancellationError {
            Logger.networking.info("\(Element.self, privacy: .public) API sequence was cancelled")
            throw error
        } catch {
            let sanitizedError = await repository.sanitizedError(error)
            Logger.networking.error("Error in \(Element.self, privacy: .public) API sequence: \(sanitizedError, privacy: .public)")
            throw error
        }
    }

    public nonisolated
    func makeAsyncIterator() -> ApiSequence {
        self
    }
}
