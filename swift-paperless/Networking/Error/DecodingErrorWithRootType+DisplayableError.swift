//
//  DecodingErrorWithRootType+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//

import Networking

extension DecodingErrorWithRootType: DisplayableError {
    var message: String {
        error.message
    }

    var details: String? {
        error.makeDetails("\(type)")
    }
}
