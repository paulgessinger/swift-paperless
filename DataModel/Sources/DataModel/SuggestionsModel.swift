//
//  SuggestionsModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.08.23.
//

import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct Suggestions: Sendable {
    public var correspondents: [UInt]
    public var tags: [UInt]
    public var documentTypes: [UInt]
    public var storagePaths: [UInt]
    public var dates: [Date]
}
