//
//  PermissionsModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.07.2024.
//

import Foundation

struct Permissions: Codable, Equatable, Hashable {
    struct Set: Codable, Equatable, Hashable {
        var users: [UInt] = []
        var groups: [UInt] = []
    }

    var view = Set()
    var change = Set()
}

protocol PermissionsModel {
    var owner: UInt? { get set }

    var permissions: Permissions? { get set }

//    var setPermissions: Permissions? { get set }
}
