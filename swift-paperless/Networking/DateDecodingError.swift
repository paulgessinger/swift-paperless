//
//  DateDecodingError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.23.
//

import Foundation

enum DateDecodingError: Error {
    case invalidDate(string: String)
}
