//
//  DocumentCreateError+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//

extension DocumentCreateError: DisplayableError {
    var message: String {
        switch self {
        case .tooLarge:
            String(localized: .localizable(.documentCreateFailedTooLarge))
        }
    }

    var details: String? {
        switch self {
        case .tooLarge:
            String(localized: .localizable(.documentCreateFailedTooLargeDetails))
        }
    }
}
