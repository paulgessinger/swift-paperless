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
    let res: LocalizedStringResource =
      switch self {
      case .invalidUrl: .deeplinks(.errorInvalidUrl)
      case .unsupportedVersion(let version):
        if let version {
          .deeplinks(.errorUnsupportedVersionWithValue(version))
        } else {
          .deeplinks(.errorUnsupportedVersion)
        }
      case .missingPath: .deeplinks(.errorMissingPath)
      case .unknownResource(let resource): .deeplinks(.errorUnknownResource(resource))
      case .missingDocumentId: .deeplinks(.errorMissingDocumentId)
      case .invalidDocumentId(let id): .deeplinks(.errorInvalidDocumentId(id))
      case .invalidEditValue(let value): .deeplinks(.errorInvalidEditValue(value))
      case .invalidTagMode(let mode): .deeplinks(.errorInvalidTagMode(mode))
      case .excludedTagsNotAllowedInAnyMode: .deeplinks(.errorExcludedTagsNotAllowedInAnyMode)
      case .invalidSearchMode(let mode): .deeplinks(.errorInvalidSearchMode(mode))
      case .invalidAsnValue(let value): .deeplinks(.errorInvalidAsnValue(value))
      case .invalidDateFormat(let value): .deeplinks(.errorInvalidDateFormat(value))
      case .invalidSortField(let value): .deeplinks(.errorInvalidSortField(value))
      case .mixedFilterIdsNotAllowed(let parameter):
        .deeplinks(.errorMixedFilterIdsNotAllowed(parameter))
      case .unsupportedModifiedDateFilter: .deeplinks(.errorUnsupportedModifiedDateFilter)
      case .unsupportedPreviousIntervalDateFilter:
        .deeplinks(.errorUnsupportedPreviousIntervalDateFilter)
      }

    return String(localized: res)
  }

  var documentationLink: URL? {
    URL(string: "https://swift-paperless.gessinger.dev/deeplinks")
  }
}
