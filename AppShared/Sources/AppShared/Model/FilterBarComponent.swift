//
//  FilterBarComponent.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.02.26.
//

import Foundation

public enum FilterBarComponent: String, CaseIterable, Codable {
  case tags
  case documentType
  case correspondent
  case storagePath
  case permissions
  case customFields
  case asn
  case date

  public var localizedName: LocalizedStringResource {
    switch self {
    case .tags: .localizable(.tags)
    case .documentType: .localizable(.documentType)
    case .correspondent: .localizable(.correspondent)
    case .storagePath: .localizable(.storagePath)
    case .permissions: .localizable(.permissions)
    case .customFields: .localizable(.customFields)
    case .asn: .localizable(.asn)
    case .date: .localizable(.dateFilterTitle)
    }
  }
}

public enum FilterBarConfiguration: Equatable, Codable {
  case `default`
  case configured([FilterBarComponent])
}
