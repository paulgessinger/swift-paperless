//
//  Compatibility.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.04.2024.
//

import Foundation

// KeyPath is not Sendable
// https://github.com/apple/swift/issues/57560
extension KeyPath: @unchecked Sendable {}
