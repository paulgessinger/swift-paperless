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

  public init(resource: UserPermissions.Resource, operation: UserPermissions.Operation) {
    self.resource = resource
    self.operation = operation
  }

  public var message: String {
    String(localized: .localizable(.apiForbiddenErrorMessage(resource.localizedName)))
  }

  public var details: String? {
    String(localized: .localizable(.apiForbiddenDetails(resource.localizedName)))
  }

  public var documentationLink: URL? { DocumentationLinks.forbidden }
}
