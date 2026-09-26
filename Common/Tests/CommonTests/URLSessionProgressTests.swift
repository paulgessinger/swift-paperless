//
//  URLSessionProgressTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

// Own URLProtocol subclass, so this suite shares no global responder with others.
// Hands over the whole body in one go, as a fast transfer does.
private final class ProgressMockURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(repeating: 0xab, count: 8192))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite("URLSession progress reporting")
struct URLSessionProgressTests {
  private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
  }

  private static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ProgressMockURLProtocol.self]
    return URLSession(configuration: config)
  }

  private static let request = URLRequest(url: URL(string: "https://example.com/doc.pdf")!)

  /// Blocks the calling thread; synchronous so it can hold the main actor from
  /// an async test.
  @MainActor
  private static func holdMainActor() {
    Thread.sleep(forTimeInterval: 0.5)
  }

  // Holding the main actor for the whole transfer is what a loaded CI runner
  // does by accident: progress must not depend on the main actor getting a
  // turn before the task finishes.
  @Test("download progress arrives while the main actor is busy")
  @MainActor
  func downloadProgressWithBusyMainActor() async throws {
    let session = Self.makeSession()
    let calls = Calls()
    let download = Task.detached {
      try await session.getDownload(for: Self.request, progress: { _ in calls.bump() })
    }
    Self.holdMainActor()
    let (url, _) = try await download.value
    try? FileManager.default.removeItem(at: url)

    #expect(calls.value >= 1)
  }

  @Test("data progress arrives while the main actor is busy")
  @MainActor
  func dataProgressWithBusyMainActor() async throws {
    let session = Self.makeSession()
    let calls = Calls()
    let fetch = Task.detached {
      try await session.getData(for: Self.request, progress: { _ in calls.bump() })
    }
    Self.holdMainActor()
    _ = try await fetch.value

    #expect(calls.value >= 1)
  }
}
