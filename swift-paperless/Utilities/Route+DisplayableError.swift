//
//  Route+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.01.26.
//

import Foundation

extension Route.ParseError: DisplayableError {
  var message: String {
    String(localized: .deeplinks(.errorTitle))
  }

  var details: String? {
    switch self {
    case .invalidUrl:
      return String(localized: .deeplinks(.errorInvalidUrl))
    case .unsupportedVersion(let version):
      if let version {
        return String(localized: .deeplinks(.errorUnsupportedVersionWithValue(version)))
      } else {
        return String(localized: .deeplinks(.errorUnsupportedVersion))
      }
    case .missingPath:
      return String(localized: .deeplinks(.errorMissingPath))
    case .unknownResource(let resource):
      return String(localized: .deeplinks(.errorUnknownResource(resource)))
    case .missingDocumentId:
      return String(localized: .deeplinks(.errorMissingDocumentId))
    case .invalidDocumentId(let id):
      return String(localized: .deeplinks(.errorInvalidDocumentId(id)))
    case .invalidTagMode(let mode):
      return String(localized: .deeplinks(.errorInvalidTagMode(mode)))
    case .excludedTagsNotAllowedInAnyMode:
      return String(localized: .deeplinks(.errorExcludedTagsNotAllowedInAnyMode))
    case .invalidSearchMode(let mode):
      return String(localized: .deeplinks(.errorInvalidSearchMode(mode)))
    case .invalidAsnValue(let value):
      return String(localized: .deeplinks(.errorInvalidAsnValue(value)))
    case .invalidDateFormat(let value):
      return String(localized: .deeplinks(.errorInvalidDateFormat(value)))
    case .invalidSortField(let value):
      return String(localized: .deeplinks(.errorInvalidSortField(value)))
    case .mixedFilterIdsNotAllowed(let parameter):
      return String(localized: .deeplinks(.errorMixedFilterIdsNotAllowed(parameter)))
    case .unsupportedModifiedDateFilter:
      return String(localized: .deeplinks(.errorUnsupportedModifiedDateFilter))
    case .unsupportedPreviousIntervalDateFilter:
      return String(localized: .deeplinks(.errorUnsupportedPreviousIntervalDateFilter))
    }
  }

  var documentationLink: URL? {
    URL(string: "https://swift-paperless.gessinger.dev/deeplinks")
  }
}
