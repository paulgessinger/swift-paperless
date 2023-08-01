//
//  DocumentTypeModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

protocol DocumentTypeProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

struct DocumentType:
    Codable,
    Hashable,
    Identifiable,
    Model,
    DocumentTypeProtocol,
    Named
{
    var id: UInt
    var name: String
    var slug: String

    var match: String
    var matchingAlgorithm: MatchingAlgorithm
    var isInsensitive: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, slug
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}

struct ProtoDocumentType: Codable, Hashable, DocumentTypeProtocol {
    var name: String = ""

    var match: String = ""
    var matchingAlgorithm: MatchingAlgorithm = .auto
    var isInsensitive: Bool = false

    private enum CodingKeys: String, CodingKey {
        case name
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }
}
