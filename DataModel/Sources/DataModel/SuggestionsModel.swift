//
//  SuggestionsModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.08.23.
//

import Foundation

public struct Suggestions: Codable, Sendable {
    public var correspondents: [UInt]
    public var tags: [UInt]
    public var documentTypes: [UInt]
    public var storagePaths: [UInt]
    public var dates: [Date]

    public init(correspondents: [UInt] = [], tags: [UInt] = [], documentTypes: [UInt] = [], storagePaths: [UInt] = [], dates: [Date] = []) {
        self.correspondents = correspondents
        self.tags = tags
        self.documentTypes = documentTypes
        self.storagePaths = storagePaths
        self.dates = dates
    }

    private enum CodingKeys: String, CodingKey {
        case correspondents, tags
        case documentTypes = "document_types"
        case storagePaths = "storage_paths"
        case dates
    }
}
