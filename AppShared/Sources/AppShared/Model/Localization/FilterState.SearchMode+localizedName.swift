//
//  FilterState.SearchMode+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

import DataModel

extension FilterState.SearchMode {
  public var localizedName: String {
    switch self {
    case .title:
      String(localized: .app(.searchTitle))
    case .content:
      String(localized: .app(.searchContent))
    case .titleContent:
      String(localized: .app(.searchTitleContent))
    case .advanced:
      String(localized: .app(.searchAdvanced))
    }
  }
}
