//
//  UserModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.07.23.
//

import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct User: Model, Identifiable, Equatable, Sendable {
    public var id: UInt
    @CodedAt("is_superuser")
    public var isSuperUser: Bool
    public var username: String
}

@Codable
@MemberInit
public struct UserGroup: Model, Identifiable, Equatable, Sendable {
    public var id: UInt
    public var name: String
}
