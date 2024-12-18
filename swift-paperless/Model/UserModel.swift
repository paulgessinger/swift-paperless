//
//  UserModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.07.23.
//

import DataModel
import Foundation

struct User: Codable, Model, Identifiable, Equatable {
    var id: UInt
    var isSuperUser: Bool
    var username: String

    private enum CodingKeys: String, CodingKey {
        case id, username
        case isSuperUser = "is_superuser"
    }

    static var localizedName: String { String(localized: .localizable(.user)) }
}

struct UserGroup: Codable, Identifiable, Equatable, Model {
    var id: UInt
    var name: String

    static var localizedName: String { String(localized: .localizable(.group)) }
}
