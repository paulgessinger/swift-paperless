//
//  DocumentTypeModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

public protocol DocumentTypeProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

public struct DocumentType:
    Codable,
    Hashable,
    Identifiable,
    Model,
    DocumentTypeProtocol,
    Named,
    Sendable
{
    public var id: UInt
    public var name: String
    public var slug: String

    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool

    public init(id: UInt, name: String, slug: String, match: String, matchingAlgorithm: MatchingAlgorithm, isInsensitive: Bool) {
        self.id = id
        self.name = name
        self.slug = slug
        self.match = match
        self.matchingAlgorithm = matchingAlgorithm
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}

public struct ProtoDocumentType: Codable, Hashable, DocumentTypeProtocol, Sendable {
    public var name: String

    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool

    public init(name: String = "", match: String = "", matchingAlgorithm: MatchingAlgorithm = .auto, isInsensitive: Bool = false) {
        self.name = name
        self.match = match
        self.matchingAlgorithm = matchingAlgorithm
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}
