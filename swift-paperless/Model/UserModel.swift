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

    static var localizedName: String { String(localized: .localizable(.user)) }
}

struct UserGroup: Codable, Identifiable, Equatable, Model {
    var id: UInt
    var name: String

    static var localizedName: String { String(localized: .localizable(.group)) }
}

struct UserPermissions: Decodable {
    enum Operation: Int, CaseIterable {
        case view
        case add
        case change
        case delete
    }

    struct PermissionSet {
        var values = [Bool](repeating: false, count: Operation.allCases.count)

        func test(_ operation: Operation) -> Bool {
            values[operation.rawValue]
        }

        mutating func set(_ operation: Operation, to value: Bool = true) {
            values[operation.rawValue] = value
        }
    }

    enum Resource: String, CaseIterable {
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

    func test(_ operation: Operation, for resource: Resource) -> Bool {
        guard let rule = rules[resource] else {
            return false
        }

        return rule.test(operation)
    }

    init(from decoder: any Decoder) throws {
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
