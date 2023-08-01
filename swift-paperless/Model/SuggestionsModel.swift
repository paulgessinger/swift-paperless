//
//  Suggestions.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.08.23.
//

import Foundation

struct Suggestions: Codable {
    var correspondents: [UInt] = []
    var tags: [UInt] = []
    var documentTypes: [UInt] = []
    var storagePaths: [UInt] = []
    var dates: [Date] = []

    private enum CodingKeys: String, CodingKey {
        case correspondents, tags
        case documentTypes = "document_types"
        case storagePaths = "storage_paths"
        case dates
    }
}
