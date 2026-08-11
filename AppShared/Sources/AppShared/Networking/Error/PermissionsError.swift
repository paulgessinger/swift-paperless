//
//  PermissionsError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.01.25.
//

import DataModel
import Foundation

public struct PermissionsError: Error, DisplayableError {
  public let resource: UserPermissions.Resource
  public let operation: UserPermissions.Operation

  /// What the backend said when it rejected the request. `nil` when the
  /// client-side permission check refused the operation before it went out.
  public let detail: String?

  public init(
    resource: UserPermissions.Resource, operation: UserPermissions.Operation,
    detail: String? = nil
  ) {
    self.resource = resource
    self.operation = operation
    self.detail = detail
  }

  /// Names the operation, not the resource: "no access to storage paths" is
  /// confusing when the user is looking at a list of them and only the delete
  /// was refused. The resource goes in `details` — this is the toast message,
  /// which is one line with tail truncation, so it has to stay short.
  public var message: String {
    switch operation {
    case .view: String(localized: .app(.apiForbiddenViewErrorMessage))
    case .add: String(localized: .app(.apiForbiddenAddErrorMessage))
    case .change: String(localized: .app(.apiForbiddenChangeErrorMessage))
    case .delete: String(localized: .app(.apiForbiddenDeleteErrorMessage))
    }
  }

  public var details: String? {
    let name = resource.localizedNamePlural
    var msg =
      switch operation {
      case .view: String(localized: .app(.apiForbiddenViewDetails(name)))
      case .add: String(localized: .app(.apiForbiddenAddDetails(name)))
      case .change: String(localized: .app(.apiForbiddenChangeDetails(name)))
      case .delete: String(localized: .app(.apiForbiddenDeleteDetails(name)))
      }
    if let detail {
      msg += "\n\n\(detail)"
    }
    return msg
  }

  public var documentationLink: URL? { DocumentationLinks.forbidden }
}
