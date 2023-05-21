//
//  Model.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import AsyncAlgorithms
import Foundation
import OrderedCollections
import SwiftUI

protocol MatchingModel {
    var match: String { get set }
    var matchingAlgorithm: MatchingAlgorithm { get set }
    var isInsensitive: Bool { get set }
}

protocol DocumentProtocol: Codable {
    var documentType: UInt? { get set }
    var correspondent: UInt? { get set }
    var tags: [UInt] { get set }
}

protocol Model {
    var id: UInt { get }
}

struct Document: Identifiable, Equatable, Hashable, Model, DocumentProtocol {
    var id: UInt
    var title: String
    var documentType: UInt?
    var correspondent: UInt?
    var created: Date
    var tags: [UInt]

    private(set) var added: String? = nil
    private(set) var storagePath: UInt? = nil

    private enum CodingKeys: String, CodingKey {
        case id, title
        case documentType = "document_type"
        case correspondent, created, tags, added
        case storagePath = "storage_path"
    }
}

struct ProtoDocument: DocumentProtocol {
    var title: String = ""
    var documentType: UInt? = nil
    var correspondent: UInt? = nil
    var tags: [UInt] = []
    var created: Date = .now
}

extension Document: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(added, forKey: .added)
        try container.encode(title, forKey: .title)
        try container.encode(documentType, forKey: .documentType)
        try container.encode(correspondent, forKey: .correspondent)
        try container.encode(created, forKey: .created)
        try container.encode(tags, forKey: .tags)
        try container.encode(storagePath, forKey: .storagePath)
    }
}

protocol CorrespondentProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

struct Correspondent: Codable, Hashable, Identifiable, Model, CorrespondentProtocol {
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

protocol DocumentTypeProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

struct DocumentType:
    Codable,
    Hashable,
    Identifiable,
    Model,
    DocumentTypeProtocol
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

enum MatchingAlgorithm: Int, Codable, CaseIterable {
    case none, any, all, literal, regex, fuzzy, auto

    var title: String {
        switch self {
        case .none:
            return "None"
        case .any:
            return "Any"
        case .all:
            return "All"
        case .literal:
            return "Exact"
        case .regex:
            return "RegEx"
        case .fuzzy:
            return "Fuzzy"
        case .auto:
            return "Auto"
        }
    }

    var label: String {
//        var result = title + ": "
        var result = ""
        switch self {
        case .none:
            result += "No automatic matching"
        case .any:
            result += "Document contains any of these words (space separated)"
        case .all:
            result += "Document contains all of these words (space separated)"
        case .literal:
            result += "Document contains this string"
        case .regex:
            result += "Document matches this regular expression"
        case .fuzzy:
            result += "Document contains a word similar to this word"
        case .auto:
            result += "Learn matching automatically"
        }
        return result
    }
}

protocol TagProtocol: Equatable, MatchingModel {
    var isInboxTag: Bool { get set }
    var name: String { get set }
    var slug: String { get set }
    var color: HexColor { get set }
    var textColor: HexColor { get }

    static func placeholder(_ length: Int) -> Self
}

extension TagProtocol {
    var textColor: HexColor {
        // https://github.com/paperless-ngx/paperless-ngx/blob/0dcfb97824b6184094290138fe401d8368722483/src/documents/serialisers.py#L317-L328

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color.color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = sqrt(0.299 * pow(red, 2) + 0.587 * pow(green, 2) + 0.114 * pow(blue, 2))

        return HexColor(luminance < 0.53 ? .white : .black)
    }
}

struct ProtoTag: Encodable, TagProtocol, MatchingModel {
    var isInboxTag: Bool = false
    var name: String = ""
    var slug: String = ""
    var color: HexColor = Color.gray.hex

    var match: String = ""
    var matchingAlgorithm: MatchingAlgorithm = .auto
    var isInsensitive: Bool = true

    private enum CodingKeys: String, CodingKey {
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    static func placeholder(_ length: Int) -> Self {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let name = String((0 ..< length).map { _ in letters.randomElement()! })
        return .init(
            isInboxTag: false,
            name: name,
            slug: "",
            color: Color("ElementBackground").hex
        )
    }
}

struct Tag: Codable, Identifiable, Model, TagProtocol, MatchingModel, Equatable {
    var id: UInt
    var isInboxTag: Bool
    var name: String
    var slug: String
    var color: HexColor

    var match: String
    var matchingAlgorithm: MatchingAlgorithm
    var isInsensitive: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    static func placeholder(_ length: Int) -> Self {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let name = String((0 ..< length).map { _ in letters.randomElement()! })
        return .init(
            id: 0,
            isInboxTag: false,
            name: name,
            slug: "",
            color: Color("ElementBackground").hex,
            match: "",
            matchingAlgorithm: .auto,
            isInsensitive: true
        )
    }
}

extension Tag: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

protocol SavedViewProtocol: Codable {
    var name: String { get set }
    var showOnDashboard: Bool { get set }
    var showInSidebar: Bool { get set }
    var sortField: SortField { get set }
    var sortOrder: SortOrder { get set }
    var filterRules: [FilterRule] { get set }
}

struct SavedView: Codable, Identifiable, Hashable, Model, SavedViewProtocol {
    var id: UInt
    var name: String
    var showOnDashboard: Bool
    var showInSidebar: Bool
    var sortField: SortField
    var sortOrder: SortOrder
    var filterRules: [FilterRule]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortOrder = "sort_reverse"
        case filterRules = "filter_rules"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ProtoSavedView: Codable, SavedViewProtocol {
    var name: String = ""
    var showOnDashboard: Bool = false
    var showInSidebar: Bool = false
    var sortField: SortField = .created
    var sortOrder: SortOrder = .descending
    var filterRules: [FilterRule] = []

    private enum CodingKeys: String, CodingKey {
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortOrder = "sort_reverse"
        case filterRules = "filter_rules"
    }
}
