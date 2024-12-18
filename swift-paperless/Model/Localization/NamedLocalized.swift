//
//  NamedLocalized.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.12.2024.
//

import DataModel
import Foundation

protocol NamedLocalized {
    static var localizedName: String { get }
}

extension Document: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.document)) }
}

extension SortField {
    var localizedName: String {
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

extension Tag: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.tag)) }
}

extension User: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.user)) }
}

extension UserGroup: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.group)) }
}

extension DocumentType: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.documentType)) }
}

extension Correspondent: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.correspondent)) }
}

extension SavedView: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.savedView)) }
}

extension StoragePath: NamedLocalized {
    static var localizedName: String { String(localized: .localizable(.storagePath)) }
}

// extension Correspondent : NamedLocalized {
// }
