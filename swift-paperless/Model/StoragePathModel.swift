//
//  StoragePathModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import DataModel
import Foundation

protocol StoragePathProtocol: Codable, MatchingModel {
    var name: String { get set }
    var path: String { get set }
}

struct StoragePath: StoragePathProtocol, Model, Identifiable, Hashable, Named {
    var id: UInt
    var name: String
    var path: String
    var slug: String

    var matchingAlgorithm: MatchingAlgorithm
    var match: String
    var isInsensitive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, path, slug

        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    static var localizedName: String { String(localized: .localizable(.storagePath)) }
}

struct ProtoStoragePath: StoragePathProtocol {
    var name: String = ""
    var path: String = ""

    var matchingAlgorithm: MatchingAlgorithm = .auto
    var match: String = ""
    var isInsensitive: Bool = false

    private enum CodingKeys: String, CodingKey {
        case name, path
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}
