//
//  Error+isCancellationError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.25.
//

import Common
import Foundation

extension Error {
    var isCancellationError: Bool {
        if self is CancellationError {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && NSURLError(rawValue: nsError.code) == NSURLError.cancelled
    }
}
