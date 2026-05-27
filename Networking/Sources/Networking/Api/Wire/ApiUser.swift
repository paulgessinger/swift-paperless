//
//  ApiUser.swift
//  Networking
//

import DataModel

// MARK: - Wire types for reading users and groups

struct ApiUser: Codable, Sendable {
  var id: UInt
  var is_superuser: Bool
  var username: String
  var groups: [UInt]?
}

extension ApiUser {
  var domain: User {
    User(
      id: id,
      isSuperUser: is_superuser,
      username: username,
      groups: groups ?? []
    )
  }
}

struct ApiUserGroup: Codable, Sendable {
  var id: UInt
  var name: String
}

extension ApiUserGroup {
  var domain: UserGroup {
    UserGroup(id: id, name: name)
  }
}

// MARK: - Wire type for the user-permissions matrix

/// The API returns user permissions as a flat string array (e.g.
/// `["view_document", "change_tag", ...]`). This wire type owns the decoding,
/// leaving `DataModel.UserPermissions` free of Codable.
struct ApiUserPermissions: Codable, Sendable {
  let values: [String]

  init(values: [String]) {
    self.values = values
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    values = try container.decode([String].self)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(values)
  }
}

extension ApiUserPermissions {
  var domain: UserPermissions {
    var rules = UserPermissions.Resource.allCases.reduce(
      into: [UserPermissions.Resource: UserPermissions.PermissionSet]()
    ) {
      $0[$1] = UserPermissions.PermissionSet()
    }

    for value in values {
      let parts = value.split(separator: "_", maxSplits: 1)
      guard parts.count == 2,
        let resource = UserPermissions.Resource(rawValue: String(parts[1])),
        let op = UserPermissions.Operation(parts[0])
      else { continue }
      rules[resource]?.set(op, to: true)
    }

    return UserPermissions(rules: rules)
  }
}

extension ApiUserPermissions {
  init(from permissions: UserPermissions) {
    var values: [String] = []
    for resource in UserPermissions.Resource.allCases {
      let permSet = permissions[resource]
      for op in UserPermissions.Operation.allCases where permSet.test(op) {
        values.append("\(op.description)_\(resource.rawValue)")
      }
    }
    self.values = values
  }
}
