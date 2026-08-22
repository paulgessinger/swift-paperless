//
//  URLSession+data.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.2024.
//

import Foundation

// This is here because URLSession.shared.data is otherwise not callable from nonisolated without a warning
// https://forums.developer.apple.com/forums/thread/727823
extension URLSession {
  public nonisolated func getData(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await data(for: request, delegate: nil)
  }

  /// - Parameter onTransfer: reports the bytes this request actually put on the
  ///   wire, once the task's metrics land. Header and body, in both directions,
  ///   summed across redirects and retries. These are *transport* counts: a
  ///   gzipped response reports its compressed size, and a response served from
  ///   `URLCache` reports no body bytes at all — which is what a data meter
  ///   wants and what `Data.count` at the call site cannot tell you.
  public nonisolated func getData(
    for request: URLRequest,
    progress: (@Sendable (Double) -> Void)?,
    onTransfer: (@Sendable (_ sent: Int64, _ received: Int64) -> Void)? = nil
  )
    async throws -> (Data, URLResponse)
  {
    final class Delegate: NSObject, URLSessionTaskDelegate {
      let callback: (@Sendable (Double) -> Void)?
      let onTransfer: (@Sendable (Int64, Int64) -> Void)?

      @MainActor
      private var progressObservation: NSKeyValueObservation? = nil

      init(
        _ callback: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (Int64, Int64) -> Void)? = nil
      ) {
        self.callback = callback
        self.onTransfer = onTransfer
      }

      func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        // task is Sendable, so we send that to the main actor and then store the observation in the main isolated variable
        Task { @MainActor in
          let callback = callback
          progressObservation = task.progress.observe(\.fractionCompleted) { progress, _ in
            callback?(progress.fractionCompleted)
          }
        }
      }

      func urlSession(
        _: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics
      ) {
        guard let onTransfer else { return }
        var sent: Int64 = 0
        var received: Int64 = 0
        for transaction in metrics.transactionMetrics {
          sent += transaction.countOfRequestHeaderBytesSent
          sent += transaction.countOfRequestBodyBytesSent
          received += transaction.countOfResponseHeaderBytesReceived
          received += transaction.countOfResponseBodyBytesReceived
        }
        onTransfer(sent, received)
      }
    }

    let delegate = Delegate(progress, onTransfer: onTransfer)

    return try await data(for: request, delegate: delegate)
  }
}
