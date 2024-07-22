//
//  Compatibility.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.2024.
//

import Foundation

// This is here because URLSession.shared.data is otherwise not callable from nonisolated without a warning
// https://forums.developer.apple.com/forums/thread/727823
public extension URLSession {
    nonisolated func getData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }

    nonisolated func getData(for request: URLRequest, delegate: (any URLSessionTaskDelegate)?) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: delegate)
    }

    nonisolated func getData(for url: URL) async throws -> (Data, URLResponse) {
        try await data(from: url)
    }
}
