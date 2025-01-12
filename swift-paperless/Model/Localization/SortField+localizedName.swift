//
//  SortField+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

import DataModel
import Foundation

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
