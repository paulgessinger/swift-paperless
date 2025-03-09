//
//  ResourceForbidden+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//

extension ResourceForbidden<Resource>: DisplayableError where Resource: Model & NamedLocalized {
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

    var documentationLink: URL? { DocumentationLinks.forbidden }
}
