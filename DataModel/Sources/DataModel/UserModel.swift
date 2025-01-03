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

public struct UserPermissions: Decodable {
    public enum Operation: Int, CaseIterable {
        case view
        case add
        case change
        case delete
    }

    public struct PermissionSet {
        public var values = [Bool](repeating: false, count: Operation.allCases.count)

        public func test(_ operation: Operation) -> Bool {
            values[operation.rawValue]
        }

        public mutating func set(_ operation: Operation, to value: Bool = true) {
            values[operation.rawValue] = value
        }
    }

    public enum Resource: String, CaseIterable {
        case document
        case tag
        case correspondent
        case documentType = "documenttype"
        case storagePath = "storagepath"
        case savedView = "savedview"
        case paperlessTask = "paperlesstask"
        case appConfig = "appconfig"
        case uiSettings = "uisettings"
        case history
        case note
        case mailAccount = "mailaccount"
        case mailRule = "mailrule"
        case user
        case group
        case shareLink = "sharelink"
        case customField
        case workflow
    }

    private let rules: [Resource: PermissionSet]

    public func test(_ operation: Operation, for resource: Resource) -> Bool {
        guard let rule = rules[resource] else {
            return false
        }

        return rule.test(operation)
    }

    public init(from decoder: any Decoder) throws {
        var rules = Resource.allCases.reduce(into: [Resource: PermissionSet]()) {
            $0[$1] = PermissionSet()
        }

        let container = try decoder.singleValueContainer()
        let values = try container.decode([String].self)

        for value in values {
            let parts = value.split(separator: "_", maxSplits: 1)

            let opString = parts[0]
            guard let resource = Resource(rawValue: String(parts[1])) else {
                continue
            }

            let op: Operation? = switch opString {
            case "view": .view
            case "add": .add
            case "change": .change
            case "delete": .delete
            default: nil
            }

            if let op {
                rules[resource]?.set(op, to: true)
            }
        }

        self.rules = rules
    }
}
