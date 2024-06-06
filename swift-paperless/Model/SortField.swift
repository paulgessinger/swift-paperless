//
//  SortField.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.06.2024.
//

import Foundation

enum SortField: RawRepresentable, Codable, CaseIterable, Equatable, Hashable {
    case asn
    case correspondent
    case title
    case documentType
    case created
    case added
    case modified
    case storagePath
    case owner

    case other(_: String)

    init?(rawValue: String) {
        self = switch rawValue {
        case "archive_serial_number": .asn
        case "correspondent__name": .correspondent
        case "title": .title
        case "document_type__name": .documentType
        case "created": .created
        case "added": .added
        case "modified": .modified
        case "storagePath": .storagePath
        case "owner": .owner
        default: .other(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .asn: "archive_serial_number"
        case .correspondent: "correspondent__name"
        case .title: "title"
        case .documentType: "document_type__name"
        case .created: "created"
        case .added: "added"
        case .modified: "modified"
        case .storagePath: "storagePath"
        case .owner: "owner"
        case let .other(field): field
        }
    }

    static let allCases: [SortField] = [
        .asn, .correspondent, .title, .documentType, .created, .added, .modified, .storagePath, .owner,
    ]

    var localizedName: String {
        switch self {
        case .asn:
            return String(localized: .localizable.asn)
        case .correspondent:
            return String(localized: .localizable.correspondent)
        case .title:
            return String(localized: .localizable.title)
        case .documentType:
            return String(localized: .localizable.documentType)
        case .created:
            return String(localized: .localizable.sortOrderCreated)
        case .added:
            return String(localized: .localizable.sortOrderAdded)
        case .modified:
            return String(localized: .localizable.sortOrderModified)
        case .storagePath:
            return String(localized: .localizable.sortOrderStoragePath)
        case .owner:
            return String(localized: .localizable.sortOrderOwner)
        case let .other(field):
            return field
        }
    }
}
