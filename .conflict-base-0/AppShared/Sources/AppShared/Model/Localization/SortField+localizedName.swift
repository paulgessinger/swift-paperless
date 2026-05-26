//
//  SortField+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.01.25.
//

import DataModel
import Foundation

extension SortField {
  public func localizedName(customFields: [UInt: CustomField]) -> String {
    switch self {
    case .asn: String(localized: .app(.asn))
    case .correspondent: String(localized: .app(.correspondent))
    case .title: String(localized: .app(.title))
    case .documentType: String(localized: .app(.documentType))
    case .created: String(localized: .app(.sortOrderCreated))
    case .added: String(localized: .app(.sortOrderAdded))
    case .modified: String(localized: .app(.sortOrderModified))
    case .storagePath: String(localized: .app(.sortOrderStoragePath))
    case .owner: String(localized: .app(.sortOrderOwner))
    case .notes: String(localized: .app(.sortOrderNotes))
    case .score: String(localized: .app(.sortOrderScore))
    case .pageCount: String(localized: .app(.sortOrderPageCount))
    case .customField(let id):
      if let field = customFields[id] {
        field.name
      } else {
        String(localized: .app(.sortOrderCustomFieldUnknown(id)))
      }
    case .other(let name): name
    }
  }
}
