//
//  UserModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.07.23.
//

import Foundation

public struct User: Codable, Model, Identifiable, Equatable, Sendable {
    public var id: UInt
    public var isSuperUser: Bool
    public var username: String

    public init(id: UInt, isSuperUser: Bool, username: String) {
        self.id = id
        self.isSuperUser = isSuperUser
        self.username = username
    }

    private enum CodingKeys: String, CodingKey {
        case id, username
        case isSuperUser = "is_superuser"
    }
}

public struct UserGroup: Codable, Identifiable, Equatable, Model, Sendable {
    public var id: UInt
    public var name: String

    public init(id: UInt, name: String) {
        self.id = id
        self.name = name
    }
}
