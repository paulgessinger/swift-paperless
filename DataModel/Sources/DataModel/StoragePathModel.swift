//
//  StoragePathModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

public protocol StoragePathProtocol: Codable, MatchingModel {
    var name: String { get set }
    var path: String { get set }
}

public struct StoragePath:
    StoragePathProtocol, Model, Identifiable, Hashable, Named, Sendable
{
    public var id: UInt
    public var name: String
    public var path: String
    public var slug: String

    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool

    public init(id: UInt, name: String, path: String, slug: String, matchingAlgorithm: MatchingAlgorithm, match: String, isInsensitive: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.slug = slug
        self.matchingAlgorithm = matchingAlgorithm
        self.match = match
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, path, slug

        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}

public struct ProtoStoragePath: StoragePathProtocol, Sendable {
    public var name: String
    public var path: String

    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool

    public init(name: String = "", path: String = "", matchingAlgorithm: MatchingAlgorithm = .none, match: String = "", isInsensitive: Bool = false) {
        self.name = name
        self.path = path
        self.matchingAlgorithm = matchingAlgorithm
        self.match = match
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case name, path
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}
