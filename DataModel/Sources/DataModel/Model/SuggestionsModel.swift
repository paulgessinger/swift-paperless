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
    @Default([UInt]())
    public var correspondents: [UInt]

    @Default([UInt]())
    public var tags: [UInt]

    @Default([UInt]())
    public var documentTypes: [UInt]

    @Default([UInt]())
    public var storagePaths: [UInt]

    @Default([Date]())
    public var dates: [Date]
}
