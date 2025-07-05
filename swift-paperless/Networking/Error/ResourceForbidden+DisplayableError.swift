//
//  ResourceForbidden+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//

import DataModel
import Foundation
import Networking

extension ResourceForbidden: DisplayableError where Resource: Model & LocalizedResource {
  var message: String {
    String(localized: .localizable(.apiForbiddenErrorMessage(Resource.localizedName)))
  }

  var details: String? {
    var msg = String(localized: .localizable(.apiForbiddenDetails(Resource.localizedName)))
    if let response {
      msg += "\n\n\(response)"
    }
    return msg
  }
}

extension ResourceForbidden: DocumentedError {
  var documentationLink: URL? { DocumentationLinks.forbidden }
}
