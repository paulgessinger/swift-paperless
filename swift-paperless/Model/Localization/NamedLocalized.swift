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
        switch self {
        case .asn: String(localized: .localizable(.asn))
        case .correspondent: String(localized: .localizable(.correspondent))
        case .title: String(localized: .localizable(.title))
        case .documentType: String(localized: .localizable(.documentType))
        case .created: String(localized: .localizable(.sortOrderCreated))
        case .added: String(localized: .localizable(.sortOrderAdded))
        case .modified: String(localized: .localizable(.sortOrderModified))
        case .storagePath: String(localized: .localizable(.sortOrderStoragePath))
        case .owner: String(localized: .localizable(.sortOrderOwner))
        case .notes: String(localized: .localizable(.sortOrderNotes))
        case .score: String(localized: .localizable(.sortOrderScore))
        case .pageCount: String(localized: .localizable(.sortOrderPageCount))
        case let .other(name): name
        }
    }
}

extension DataModel.SortOrder {
    var localizedName: String {
        switch self {
        case .ascending:
            String(localized: .localizable(.ascending))
        case .descending:
            String(localized: .localizable(.descending))
        }
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

extension FilterState.SearchMode {
    var localizedName: String {
        switch self {
        case .title:
            String(localized: .localizable(.searchTitle))
        case .content:
            String(localized: .localizable(.searchContent))
        case .titleContent:
            String(localized: .localizable(.searchTitleContent))
        case .advanced:
            String(localized: .localizable(.searchAdvanced))
        }
    }
}
