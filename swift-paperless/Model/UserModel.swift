//
//  UserModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.07.23.
//

import Foundation

struct User: Codable, Model, Identifiable, Equatable {
    var id: UInt
    var isSuperUser: Bool
    var username: String

    private enum CodingKeys: String, CodingKey {
        case id, username
        case isSuperUser = "is_superuser"
    }
}
