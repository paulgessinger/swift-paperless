//
//  PermissionsHelper.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 08.03.25.
//

public func stringOrPrivate(_ value: String?) -> String {
  value ?? String(localized: .permissions(.private))
}
