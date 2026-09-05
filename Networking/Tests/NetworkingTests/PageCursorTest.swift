import DataModel
import Foundation
import Testing

@testable import Networking

private actor RequestRecorder {
  private(set) var urls: [URL] = []
  func record(_ url: URL) { urls.append(url) }
  var count: Int { urls.count }
}

private let initial = URL(string: "https://example.com/api/items/?page=1")!

@Suite struct PageCursorTest {
  // A single-page list (server's `next` is nil on the first response) must not
  // trigger a second HTTP request to discover exhaustion. Today's `ApiSequence`
  // would issue two; the cursor issues exactly one.
  @Test func noExtraRequestWhenNextIsNil() async throws {
    let recorder = RequestRecorder()
    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { url in
        await recorder.record(url)
        return ListResponse(count: 3, next: nil, previous: nil, results: [1, 2, 3])
      })

    let first = try await cursor.nextPage()
    #expect(first?.items == [1, 2, 3])
    #expect(first?.isLast == true)
    #expect(await cursor.isExhausted)

    let second = try await cursor.nextPage()
    #expect(second == nil)
    #expect(await recorder.count == 1)
  }

  // `totalCount` from `ListResponse.count` is surfaced after the first page.
  @Test func totalCountSurfaced() async throws {
    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { _ in
        ListResponse(count: 8421, next: nil, previous: nil, results: [1])
      })

    #expect(await cursor.totalCount == nil)
    _ = try await cursor.nextPage()
    #expect(await cursor.totalCount == 8421)
  }

  // Cancellation must throw `CancellationError`, not return nil (which a
  // consumer would interpret as exhaustion).
  @Test func cancellationThrows() async throws {
    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { _ in
        try await Task.sleep(for: .seconds(5))
        return ListResponse(count: 0, next: nil, previous: nil, results: [])
      })

    let task = Task<Void, Error> {
      _ = try await cursor.nextPage()
    }
    task.cancel()

    await #expect(throws: (any Error).self) {
      try await task.value
    }
  }

  // Cancellation detected before the request fires should also throw.
  @Test func cancellationBeforeRequestThrows() async throws {
    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { _ in
        Issue.record("fetch must not be called when task is already cancelled")
        return ListResponse(count: 0, next: nil, previous: nil, results: [])
      })

    let task = Task<Void, Error> {
      try await Task.sleep(for: .milliseconds(50))
      _ = try await cursor.nextPage()
    }
    task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  // Multi-page exhaustion: after the third page (whose `next` is nil), the
  // cursor reports exhausted and never issues a fourth request.
  @Test func multiPageExhaustion() async throws {
    let urls = (1...3).map { URL(string: "https://example.com/api/items/?page=\($0)")! }
    let recorder = RequestRecorder()
    let cursor = PageCursor<Int>(
      initialURL: urls[0],
      fetch: { url in
        await recorder.record(url)
        switch url {
        case urls[0]:
          return ListResponse(count: 9, next: urls[1], previous: nil, results: [1, 2, 3])
        case urls[1]:
          return ListResponse(count: 9, next: urls[2], previous: nil, results: [4, 5, 6])
        case urls[2]:
          return ListResponse(count: 9, next: nil, previous: nil, results: [7, 8, 9])
        default:
          Issue.record("Unexpected URL: \(url)")
          throw CancellationError()
        }
      })

    let collected = try await cursor.collectAll()
    #expect(collected == [1, 2, 3, 4, 5, 6, 7, 8, 9])
    #expect(await recorder.count == 3)
    #expect(await cursor.isExhausted)
  }

  // Workaround for https://github.com/paulgessinger/swift-paperless/issues/68:
  // backends behind a TLS-terminating proxy may return next-page URLs with the
  // wrong scheme. `fixURL` rewrites the scheme before the next request fires.
  @Test func issue68NextURLSchemeIsFixed() async throws {
    let initial = URL(string: "https://example.com/api/items/?page=1")!
    let serverNext = URL(string: "http://example.com/api/items/?page=2")!
    let expectedFixed = URL(string: "https://example.com/api/items/?page=2")!
    let recorder = RequestRecorder()

    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { url in
        await recorder.record(url)
        if url == initial {
          return ListResponse(count: 4, next: serverNext, previous: nil, results: [1, 2])
        }
        return ListResponse(count: 4, next: nil, previous: nil, results: [3, 4])
      },
      fixURL: { url in
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        c.scheme = "https"
        return c.url!
      })

    _ = try await cursor.collectAll()
    #expect(await recorder.urls == [initial, expectedFixed])
  }

  // A 403 from the server is rewritten into `ResourceForbidden<Element>`, which
  // deliberately is *not* a `RequestError`: callers that want to skip a
  // forbidden resource must match on `ResourceForbiddenError`, not on
  // `RequestError`. Regression guard for
  // https://github.com/paulgessinger/swift-paperless/issues/661.
  @Test(.bug("https://github.com/paulgessinger/swift-paperless/issues/661", id: 661))
  func forbiddenIsRewrittenToResourceForbidden() async throws {
    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { _ in
        throw RequestError.forbidden(detail: "Insufficient permissions")
      })

    do {
      _ = try await cursor.nextPage()
      Issue.record("nextPage() must throw for a forbidden response")
    } catch let error {
      // The rewrite target, carrying the server detail through.
      let forbidden = try #require(error as? ResourceForbidden<Int>)
      #expect(forbidden.response == "Insufficient permissions")
      // Recognisable without knowing the element type.
      #expect(error is any ResourceForbiddenError)
      // The whole point of the rewrite: it is no longer a `RequestError`, so
      // `catch let error as RequestError` never sees it.
      #expect(!(error is RequestError))
    }
  }

  // The rewrite also applies on later pages, i.e. it is not tied to the first
  // request, and `collectAll` propagates it rather than ending the sequence.
  @Test(.bug("https://github.com/paulgessinger/swift-paperless/issues/661", id: 661))
  func forbiddenOnLaterPagePropagatesThroughCollectAll() async throws {
    let second = URL(string: "https://example.com/api/items/?page=2")!
    let cursor = PageCursor<Int>(
      initialURL: initial,
      fetch: { url in
        if url == initial {
          return ListResponse(count: 4, next: second, previous: nil, results: [1, 2])
        }
        throw RequestError.forbidden(detail: nil)
      })

    await #expect(throws: ResourceForbidden<Int>.self) {
      _ = try await cursor.collectAll()
    }
  }
}
