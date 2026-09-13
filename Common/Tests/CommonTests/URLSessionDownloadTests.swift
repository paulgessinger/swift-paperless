//
//  URLSessionDownloadTests.swift
//  Common
//

import Foundation
import Testing

@testable import Common

// Own URLProtocol subclass, so this suite shares no global responder with others.
private final class DownloadTransferMockURLProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(repeating: 0xab, count: 4096))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite("URLSession.getDownload")
struct URLSessionDownloadTests {
  private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func bump() { lock.withLock { count += 1 } }
  }

  // Foundation's metrics callback can't be faked (`URLSessionTaskMetrics` has no
  // usable initializer), and a URLProtocol stub reports no wire bytes, so this
  // checks the delegate is wired for download tasks, not the byte counts.
  @Test("reports the task's transfer once the download finishes")
  func reportsTransfer() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [DownloadTransferMockURLProtocol.self]
    let session = URLSession(configuration: config)
    let calls = Calls()

    let (url, _) = try await session.getDownload(
      for: URLRequest(url: URL(string: "https://example.com/doc.pdf")!), progress: nil
    ) { _, _ in calls.bump() }
    try? FileManager.default.removeItem(at: url)

    #expect(calls.value == 1)
  }
}
