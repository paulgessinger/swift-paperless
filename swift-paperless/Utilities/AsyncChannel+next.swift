//
//  AsyncChannel+next.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.05.2024.
//

import AsyncAlgorithms

extension AsyncChannel {
    func next() async -> Element? {
        for await next in self {
            return next
        }
        return nil
    }
}
