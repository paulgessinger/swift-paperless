//
//  ListResponse.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.23.
//

import Foundation

struct ListResponse<Element>: Decodable
    where Element: Decodable
{
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [Element]
}
