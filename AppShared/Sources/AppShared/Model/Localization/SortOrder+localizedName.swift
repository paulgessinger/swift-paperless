//
//  SortOrder+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

import DataModel

extension DataModel.SortOrder {
  public var localizedName: String {
    switch self {
    case .ascending:
      String(localized: .localizable(.ascending))
    case .descending:
      String(localized: .localizable(.descending))
    }
  }
}
