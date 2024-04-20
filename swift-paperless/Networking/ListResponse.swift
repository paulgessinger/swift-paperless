//
//  ListResponse.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.23.
//

import Foundation

struct ListResponse<Element> {
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [Element]
}

extension ListResponse: Decodable
    where Element: Decodable
{}

extension ListResponse: Sendable where Element: Sendable {}
