//
//  DatabaseError+DisplayableError.swift
//  swift-paperless
//

import Foundation
import Persistence

// DatabaseError is declared in the Persistence package without localized strings
// (matching the RequestError / OIDCError pattern). User-facing descriptions live
// here in the app layer, backed by the App string catalog.
extension DatabaseError: @retroactive LocalizedError {
  public var errorDescription: String? {
    userFacingSummary
  }

  public var failureReason: String? {
    underlyingSummary
  }
}

extension DatabaseError: DisplayableError {
  public var message: String {
    String(localized: .app(.errorDefaultMessage))
  }

  public var details: String? {
    userFacingDetail
  }
}

private extension DatabaseError {
  var detailLabel: String {
    String(localized: .app(.requestErrorDetailLabel)) + ":"
  }

  var userFacingSummary: String? {
    switch self {
    case .appGroupUnavailable(let identifier):
      String(localized: .app(.databaseErrorAppGroupUnavailable(identifier)))
    case .openFailed(let path, _):
      openFailedSummary(path: path)
    case .migrationFailed:
      String(localized: .app(.databaseErrorMigrationFailed))
    }
  }

  var underlyingSummary: String? {
    switch self {
    case .appGroupUnavailable:
      nil
    case .openFailed(_, let underlying), .migrationFailed(let underlying):
      String(describing: underlying)
    }
  }

  var userFacingDetail: String? {
    switch self {
    case .appGroupUnavailable(let identifier):
      return String(localized: .app(.databaseErrorAppGroupUnavailable(identifier)))
    case .openFailed(let path, let underlying):
      return appendUnderlying(openFailedSummary(path: path), underlying)
    case .migrationFailed(let underlying):
      return appendUnderlying(
        String(localized: .app(.databaseErrorMigrationFailed)), underlying)
    }
  }

  func openFailedSummary(path: String) -> String {
    #if DEBUG
    "Could not open the local database at \(path)."
    #else
    String(localized: .app(.databaseErrorOpenFailed))
    #endif
  }

  func appendUnderlying(_ summary: String, _ underlying: Error) -> String {
    summary + " " + detailLabel + " " + String(describing: underlying)
  }
}
