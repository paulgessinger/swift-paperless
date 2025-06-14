//
//  PermissionsModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.07.2024.
//

import Foundation

public struct Permissions: Codable, Equatable, Hashable, Sendable {
    public struct Set: Codable, Equatable, Hashable, Sendable {
        public var users: [UInt]
        public var groups: [UInt]

        public init(users: [UInt] = [], groups: [UInt] = []) {
            self.users = users
            self.groups = groups
        }

        public static var none: Set { .init() }
    }

    public var view: Set
    public var change: Set

    public init(view: Set = .none, change: Set = .none) {
        self.view = view
        self.change = change
    }

    public init(_ factory: (inout Permissions) -> Void) {
        self.init()
        factory(&self)
    }
}

public enum Owner: Codable, Equatable, Sendable, Hashable {
    case unset
    case none
    case user(UInt)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(UInt?.self)
        self = value.map { .user($0) } ?? .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unset:
            try container.encodeNil()
        case .none:
            try container.encodeNil()
        case let .user(value):
            try container.encode(value)
        }
    }
}

public protocol PermissionsModel {
    var owner: Owner { get set }

    var permissions: Permissions? { get set }

//    var setPermissions: Permissions? { get set }
}
