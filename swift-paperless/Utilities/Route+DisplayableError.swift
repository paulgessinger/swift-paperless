//
//  Route+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.01.26.
//

import Foundation

extension Route.ParseError: DisplayableError {
  var message: String {
    String(localized: .deeplinks(.deeplinkErrorTitle))
  }

  var details: String? {
    switch self {
    case .invalidUrl:
      return String(localized: .deeplinks(.deeplinkErrorInvalidUrl))
    case .unsupportedVersion(let version):
      if let version {
        return String(localized: .deeplinks(.deeplinkErrorUnsupportedVersionWithValue(version)))
      } else {
        return String(localized: .deeplinks(.deeplinkErrorUnsupportedVersion))
      }
    case .missingPath:
      return String(localized: .deeplinks(.deeplinkErrorMissingPath))
    case .unknownResource(let resource):
      return String(localized: .deeplinks(.deeplinkErrorUnknownResource(resource)))
    case .missingDocumentId:
      return String(localized: .deeplinks(.deeplinkErrorMissingDocumentId))
    case .invalidDocumentId(let id):
      return String(localized: .deeplinks(.deeplinkErrorInvalidDocumentId(id)))
    case .missingAction:
      return String(localized: .deeplinks(.deeplinkErrorMissingAction))
    case .unknownAction(let action):
      return String(localized: .deeplinks(.deeplinkErrorUnknownAction(action)))
    case .invalidTagMode(let mode):
      return String(localized: .deeplinks(.deeplinkErrorInvalidTagMode(mode)))
    case .excludedTagsNotAllowedInAnyMode:
      return String(localized: .deeplinks(.deeplinkErrorExcludedTagsNotAllowedInAnyMode))
    }
  }

  var documentationLink: URL? {
    URL(string: "https://swift-paperless.gessinger.dev/deeplinks")
  }
}
