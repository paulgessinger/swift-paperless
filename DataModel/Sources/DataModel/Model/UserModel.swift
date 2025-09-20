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

  @Default([UInt]())
  public var groups: [UInt]
}

extension User {
  public func canChange(_ resource: some PermissionsModel) -> Bool {
    if isSuperUser {
      return true
    }

    // If resource has no owner, it's accessible to all
    if resource.owner == .none || resource.owner == .unset || resource.owner == .user(id) {
      return true
    }

    guard let permissions = resource.permissions else {
      return false
    }

    if permissions.change.users.contains(id) {
      return true
    }

    for group in groups {
      if permissions.change.groups.contains(group) {
        return true
      }
    }

    return false
  }

  public func canView(_ resource: some PermissionsModel) -> Bool {
    // Change permissions imply view permissions
    if canChange(resource) {
      return true
    }

    if isSuperUser {
      return true
    }

    // If resource has no owner, it's accessible to all
    if resource.owner == .none || resource.owner == .unset || resource.owner == .user(id) {
      return true
    }

    guard let permissions = resource.permissions else {
      return false
    }

    if permissions.view.users.contains(id) {
      return true
    }

    for group in groups {
      if permissions.view.groups.contains(group) {
        return true
      }
    }

    return false
  }

  public func canDelete(_ resource: some PermissionsModel) -> Bool {
    if isSuperUser {
      return true
    }

    return resource.owner == .none || resource.owner == .unset || resource.owner == .user(id)
  }
}

@Codable
@MemberInit
public struct UserGroup: Model, Identifiable, Equatable, Sendable {
  public var id: UInt
  public var name: String
}

public struct UserPermissions: Sendable {
  public enum Operation: Int, CaseIterable, Sendable {
    case view
    case add
    case change
    case delete
  }

  public struct PermissionSet: Sendable, CustomStringConvertible, Equatable {
    public var values = [Bool](repeating: false, count: Operation.allCases.count)

    public func test(_ operation: Operation) -> Bool {
      values[operation.rawValue]
    }

    public mutating func set(_ operation: Operation, to value: Bool = true) {
      values[operation.rawValue] = value
    }

    public var description: String {
      let enabledPermissions = Operation.allCases
        .map { test($0) ? $0.description.first! : "-" }
        .map { String($0) }

      return enabledPermissions.joined(separator: "")
    }

    public static var empty: PermissionSet {
      PermissionSet()
    }
  }

  public enum Resource: String, CaseIterable, Sendable {
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
    case customField = "customfield"
    case workflow
  }

  private var rules: [Resource: PermissionSet]

  public init(rules: [Resource: PermissionSet]) {
    self.rules = rules
  }

  public func test(_ operation: Operation, for resource: Resource) -> Bool {
    guard let rule = rules[resource] else {
      return false
    }

    return rule.test(operation)
  }

  public subscript(resource: Resource) -> PermissionSet {
    rules[resource] ?? PermissionSet()
  }

  public func get(for resource: Resource) -> PermissionSet {
    rules[resource] ?? PermissionSet()
  }

  public mutating func set(_ operation: Operation, to value: Bool, for resource: Resource) {
    if rules[resource] == nil {
      rules[resource] = PermissionSet()
    }
    rules[resource]?.set(operation, to: value)
  }

  public func configure(_ fn: (inout Self) -> Void) -> Self {
    var copy = self
    fn(&copy)
    return copy
  }

  public var matrix: String {
    let maxWidth =
      Resource.allCases
      .map(\.rawValue.count)
      .max() ?? 0

    let paddingWidth = maxWidth + 1  // Add some extra spacing
    let header = " ".padding(toLength: paddingWidth, withPad: " ", startingAt: 0) + "vacd\n"

    let rows = Resource.allCases.sorted { $0.rawValue < $1.rawValue }.map { resource in
      let permSet = rules[resource] ?? PermissionSet()
      let resourceName = resource.rawValue.padding(
        toLength: paddingWidth, withPad: " ", startingAt: 0)
      return resourceName + permSet.description
    }

    return header + rows.joined(separator: "\n")
  }

  public static var empty: UserPermissions {
    UserPermissions(rules: [:])
  }

  public static var full: UserPermissions {
    var rules = [Resource: PermissionSet]()

    // Create a fully populated PermissionSet
    var fullPermissionSet = PermissionSet()
    for operation in Operation.allCases {
      fullPermissionSet.set(operation)
    }

    // Assign the full permission set to all resources
    for resource in Resource.allCases {
      rules[resource] = fullPermissionSet
    }

    return UserPermissions(rules: rules)
  }
}

extension UserPermissions: Codable {
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

      let op: Operation? = Operation(opString)

      if let op {
        rules[resource]?.set(op, to: true)
      }
    }

    self.rules = rules
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    var values: [String] = []

    for (resource, permissionSet) in rules {
      for operation in Operation.allCases {
        if permissionSet.test(operation) {
          let value = "\(operation.description)_\(resource.rawValue)"
          values.append(value)
        }
      }
    }

    try container.encode(values)
  }
}

extension UserPermissions {
  private static func build(_ initial: Self, _ configure: (inout Self) -> Void) -> Self {
    var initial = initial
    configure(&initial)
    return initial
  }

  public static func empty(with configure: (inout Self) -> Void) -> Self {
    build(.empty, configure)
  }

  public static func full(with configure: (inout Self) -> Void) -> Self {
    build(.full, configure)
  }
}

extension UserPermissions.Operation: CustomStringConvertible {
  public var description: String {
    switch self {
    case .view: "view"
    case .add: "add"
    case .change: "change"
    case .delete: "delete"
    }
  }

  public init?(_ description: some StringProtocol) {
    switch description {
    case "view": self = .view
    case "add": self = .add
    case "change": self = .change
    case "delete": self = .delete
    default: return nil
    }
  }
}

extension UserPermissions.Resource {
  public init?(for type: (some Any).Type) {
    switch type {
    case is Document.Type: self = .document
    case is Tag.Type: self = .tag
    case is Correspondent.Type: self = .correspondent
    case is DocumentType.Type: self = .documentType
    case is StoragePath.Type: self = .storagePath
    case is SavedView.Type: self = .savedView
    case is PaperlessTask.Type: self = .paperlessTask
    case is User.Type: self = .user
    case is UserGroup.Type: self = .group
    default: return nil
    }
  }
}
