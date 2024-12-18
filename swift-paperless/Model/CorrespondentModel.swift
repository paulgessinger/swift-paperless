//
//  CorrespondentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import DataModel
import Foundation

protocol CorrespondentProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

struct Correspondent: Codable, Hashable, Identifiable, Model, CorrespondentProtocol, Named, Sendable {
    var id: UInt
    var documentCount: UInt?
    var lastCorrespondence: Date?
    var name: String
    var slug: String

    var matchingAlgorithm: MatchingAlgorithm
    var match: String
    var isInsensitive: Bool

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

struct ProtoCorrespondent: Codable, CorrespondentProtocol, Hashable {
    var name: String = ""

    var matchingAlgorithm: MatchingAlgorithm = .auto
    var match: String = ""
    var isInsensitive: Bool = false

    private enum CodingKeys: String, CodingKey {
        case name
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}
