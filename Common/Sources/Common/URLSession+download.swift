//
//  URLSession+download.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.05.26.
//

import Foundation

extension URLSession {
  /// Streams the response of `request` to a temp file on disk and reports
  /// progress via KVO on `URLSessionTask.progress`. Mirrors the shape of
  /// `getData(for:progress:)` so callers can swap them with no API churn.
  ///
  /// The returned URL points into the system temp directory and is owned by
  /// the caller — `URLSession` deletes it once the delegate method returns,
  /// so the caller MUST move or replace it before this method returns.
  /// Background `URLSession`s only support download/upload tasks (not `data`),
  /// so this shape is also what a future background sync engine will need.
  ///
  /// - Parameter onTransfer: reports the bytes the download put on the wire,
  ///   once the task's metrics land. Same meaning as in
  ///   `getData(for:progress:onTransfer:)`.
  public nonisolated func getDownload(
    for request: URLRequest, progress: (@Sendable (Double) -> Void)?,
    onTransfer: (@Sendable (_ sent: Int64, _ received: Int64) -> Void)? = nil
  ) async throws -> (URL, URLResponse) {
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

      func urlSession(
        _: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics
      ) {
        guard let onTransfer else { return }
        let bytes = metrics.transferredBytes
        onTransfer(bytes.sent, bytes.received)
      }

      func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
        Task { @MainActor in
          let callback = callback
          progressObservation = task.progress.observe(\.fractionCompleted) {
            progress, _ in
            callback?(progress.fractionCompleted)
          }
        }
      }
    }

    let delegate = Delegate(progress, onTransfer: onTransfer)
    return try await download(for: request, delegate: delegate)
  }
}
