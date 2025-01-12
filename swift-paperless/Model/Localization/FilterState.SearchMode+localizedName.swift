//
//  FilterState.SearchMode+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

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
