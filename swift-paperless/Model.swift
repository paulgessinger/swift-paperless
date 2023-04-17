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

protocol DocumentProtocol: Codable {
    var documentType: UInt? { get set }
    var correspondent: UInt? { get set }
    var tags: [UInt] { get set }
}

struct Document: Identifiable, Equatable, Hashable, Model, DocumentProtocol {
    var id: UInt
    var title: String
    var documentType: UInt?
    var correspondent: UInt?
    var created: Date
    var tags: [UInt]

    private(set) var added: String? = nil
    private(set) var storagePath: String? = nil

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

struct Correspondent: Codable, Identifiable, Model {
    var id: UInt
    var documentCount: UInt
    var isInsensitive: Bool
    var lastCorrespondence: Date?
    // match?
    var name: String
    var slug: String

    private enum CodingKeys: String, CodingKey {
        case id
        case documentCount = "document_count"
        case isInsensitive = "is_insensitive"
        case lastCorrespondence = "last_correspondence"
        case name, slug
    }
}

struct DocumentType: Codable, Identifiable, Model {
    var id: UInt
    var name: String
    var slug: String

    private enum CodingKeys: String, CodingKey {
        case id, name, slug
    }
}

struct Tag: Codable, Identifiable, Model {
    var id: UInt
    var isInboxTag: Bool
    var name: String
    var slug: String
    @HexColor var color: Color
    @HexColor var textColor: Color

    private enum CodingKeys: String, CodingKey {
        case id
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case textColor = "text_color"
    }

    static func placeholder(_ length: Int) -> Tag {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let name = String((0 ..< length).map { _ in letters.randomElement()! })
        return .init(id: 0, isInboxTag: false, name: name, slug: "", color: Color.systemGroupedBackground, textColor: .white)
    }
}

extension Tag: Equatable, Hashable {
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum SortField: String, Codable, CaseIterable {
    case asn = "archive_serial_number"
    case correspondent
    case title
    case documentType = "document_type"
    case created
    case added
    case modified

    var label: String {
        switch self {
        case .asn:
            return "ASN"
        case .correspondent:
            return "Correspondent"
        case .title:
            return "Title"
        case .documentType:
            return "Document Type"
        case .created:
            return "Created"
        case .added:
            return "Added"
        case .modified:
            return "Modified"
        }
    }
}

protocol SavedViewProtocol: Codable {
    var name: String { get set }
    var showOnDashboard: Bool { get set }
    var showInSidebar: Bool { get set }
    var sortField: SortField { get set }
    var sortReverse: Bool { get set }
    var filterRules: [FilterRule] { get set }
}

struct SavedView: Codable, Identifiable, Hashable, Model, SavedViewProtocol {
    var id: UInt
    var name: String
    var showOnDashboard: Bool
    var showInSidebar: Bool
    var sortField: SortField
    var sortReverse: Bool
    var filterRules: [FilterRule]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortReverse = "sort_reverse"
        case filterRules = "filter_rules"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ProtoSavedView: Codable, SavedViewProtocol {
    var name: String
    var showOnDashboard: Bool = false
    var showInSidebar: Bool = false
    var sortField: SortField = .created
    var sortReverse: Bool = false
    var filterRules: [FilterRule] = []

    private enum CodingKeys: String, CodingKey {
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortReverse = "sort_reverse"
        case filterRules = "filter_rules"
    }
}
