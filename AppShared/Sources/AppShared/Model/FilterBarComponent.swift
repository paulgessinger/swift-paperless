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
    case .tags: .app(.tags)
    case .documentType: .app(.documentType)
    case .correspondent: .app(.correspondent)
    case .storagePath: .app(.storagePath)
    case .permissions: .app(.permissions)
    case .customFields: .app(.customFields)
    case .asn: .app(.asn)
    case .date: .app(.dateFilterTitle)
    }
  }
}

public enum FilterBarConfiguration: Equatable, Codable {
  case `default`
  case configured([FilterBarComponent])
}
