//
//  URLSession+data.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.2024.
//

import Foundation

// This is here because URLSession.shared.data is otherwise not callable from nonisolated without a warning
// https://forums.developer.apple.com/forums/thread/727823
public extension URLSession {
    nonisolated func getData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }

    nonisolated func getData(for request: URLRequest, progress: (@Sendable (Double) -> Void)?) async throws -> (Data, URLResponse) {
        final class Delegate: NSObject, URLSessionTaskDelegate {
            let callback: (@Sendable (Double) -> Void)?

            private var progressObservation: NSKeyValueObservation? = nil

            init(_ callback: (@Sendable (Double) -> Void)? = nil) {
                self.callback = callback
            }

            func urlSession(_: URLSession, didCreateTask task: URLSessionTask) {
                let callback = callback
                progressObservation = task.progress.observe(\.fractionCompleted) { progress, _ in
                    callback?(progress.fractionCompleted)
                }
            }
        }

        let delegate = Delegate(progress)

        return try await data(for: request, delegate: delegate)
    }
}
