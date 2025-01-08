//
//  PermissionsError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.01.25.
//

import DataModel
import Foundation

struct PermissionsError: Error {
    let resource: UserPermissions.Resource
    let operation: UserPermissions.Operation
}
