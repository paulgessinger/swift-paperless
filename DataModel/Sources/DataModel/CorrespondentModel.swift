//
//  CorrespondentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

public protocol CorrespondentProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

public struct Correspondent:
    Codable,
    Hashable, Identifiable, Model, CorrespondentProtocol, Named,
    Sendable
{
    public var id: UInt
    public var documentCount: UInt?
    public var lastCorrespondence: Date?
    public var name: String
    public var slug: String

    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool

    public init(id: UInt, documentCount: UInt? = nil, lastCorrespondence: Date? = nil, name: String, slug: String, matchingAlgorithm: MatchingAlgorithm, match: String, isInsensitive: Bool) {
        self.id = id
        self.documentCount = documentCount
        self.lastCorrespondence = lastCorrespondence
        self.name = name
        self.slug = slug
        self.matchingAlgorithm = matchingAlgorithm
        self.match = match
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case documentCount = "document_count"
        case lastCorrespondence = "last_correspondence"
        case name, slug

        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}

public struct ProtoCorrespondent:
    Codable,
    CorrespondentProtocol,
    Hashable,
    Sendable
{
    public var name: String

    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool

    public init(name: String = "", matchingAlgorithm: MatchingAlgorithm = .auto, match: String = "", isInsensitive: Bool = false) {
        self.name = name
        self.matchingAlgorithm = matchingAlgorithm
        self.match = match
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}
