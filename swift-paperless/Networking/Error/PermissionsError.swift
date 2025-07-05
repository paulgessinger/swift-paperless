//
//  PermissionsError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.01.25.
//

import DataModel
import Foundation

struct PermissionsError: Error, DisplayableError {
  let resource: UserPermissions.Resource
  let operation: UserPermissions.Operation

  var message: String {
    String(localized: .localizable(.apiForbiddenErrorMessage(resource.localizedName)))
  }

  var details: String? {
    String(localized: .localizable(.apiForbiddenDetails(resource.localizedName)))
  }

  var documentationLink: URL? { DocumentationLinks.forbidden }
}
