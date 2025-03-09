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
