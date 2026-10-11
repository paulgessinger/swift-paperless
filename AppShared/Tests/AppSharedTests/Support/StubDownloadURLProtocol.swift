import Foundation

/// Answers a session's requests from a responder, so a download task runs
/// through the real `URLSessionDownloadDelegate` callbacks. A responder that
/// returns `nil` leaves the task in flight.
final class StubDownloadURLProtocol: URLProtocol, @unchecked Sendable {
  typealias Responder = @Sendable (URLRequest) -> (status: Int, body: Data)?

  private static let lock = NSLock()
  nonisolated(unsafe) private static var _responder: Responder?
  nonisolated(unsafe) private static var _requests: [URLRequest] = []

  static var responder: Responder? {
    get { lock.withLock { _responder } }
    set { lock.withLock { _responder = newValue } }
  }

  /// Every request the stub saw, in order.
  static var requests: [URLRequest] { lock.withLock { _requests } }

  static func reset() {
    lock.withLock {
      _responder = nil
      _requests = []
    }
  }

  /// The stub's state is process-wide, so a test takes it for itself; the
  /// next waiter gets it when the lease is released.
  static func lease() async -> Lease {
    await Lease.queue.acquire()
    return Lease()
  }

  final class Lease: @unchecked Sendable {
    fileprivate static let queue = Queue()

    func release() {
      StubDownloadURLProtocol.reset()
      Self.queue.release()
    }
  }

  fileprivate final class Queue: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
      let taken: Bool = lock.withLock {
        if busy { return false }
        busy = true
        return true
      }
      if taken { return }
      await withCheckedContinuation { continuation in
        lock.withLock { waiters.append(continuation) }
      }
    }

    func release() {
      let next: CheckedContinuation<Void, Never>? = lock.withLock {
        if waiters.isEmpty {
          busy = false
          return nil
        }
        return waiters.removeFirst()
      }
      next?.resume()
    }
  }

  static func makeSession(delegate: URLSessionDownloadDelegate) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubDownloadURLProtocol.self]
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }

  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.withLock { Self._requests.append(request) }
    guard let responder = Self.responder else {
      client?.urlProtocol(self, didFailWithError: URLError(.unknown))
      return
    }
    guard let (status, body) = responder(request) else { return }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
