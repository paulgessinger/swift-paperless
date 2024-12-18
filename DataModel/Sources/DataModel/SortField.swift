//
//  SortField.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.06.2024.
//

import Foundation

public enum SortField: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case asn = "archive_serial_number"
    case correspondent = "correspondent__name"
    case title
    case documentType = "document_type__name"
    case created
    case added
    case modified
    case storagePath = "storage_path__name"
    case owner
    case notes
    case score

    public var localizedName: String {
        let res: LocalizedStringResource = switch self {
        case .asn: .localizable(.asn)
        case .correspondent: .localizable(.correspondent)
        case .title: .localizable(.title)
        case .documentType: .localizable(.documentType)
        case .created: .localizable(.sortOrderCreated)
        case .added: .localizable(.sortOrderAdded)
        case .modified: .localizable(.sortOrderModified)
        case .storagePath: .localizable(.sortOrderStoragePath)
        case .owner: .localizable(.sortOrderOwner)
        case .notes: .localizable(.sortOrderNotes)
        case .score: .localizable(.sortOrderScore)
        }
        return String(localized: res)
    }
}
