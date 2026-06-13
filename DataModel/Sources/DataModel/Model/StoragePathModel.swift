//
//  StoragePathModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

public protocol StoragePathProtocol: MatchingModel {
  var name: String { get set }
  var path: String { get set }
}

public struct StoragePath:
  StoragePathProtocol, Model, Identifiable, Hashable, Named, Sendable
{
  public var id: UInt
  public var name: String
  public var path: String
  public var slug: String

  public var matchingAlgorithm: MatchingAlgorithm
  public var match: String
  public var isInsensitive: Bool

  public init(
    id: UInt,
    name: String,
    path: String,
    slug: String,
    matchingAlgorithm: MatchingAlgorithm,
    match: String,
    isInsensitive: Bool
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.slug = slug
    self.matchingAlgorithm = matchingAlgorithm
    self.match = match
    self.isInsensitive = isInsensitive
  }
}

public struct ProtoStoragePath: StoragePathProtocol, Sendable {
  public var name: String
  public var path: String
  public var matchingAlgorithm: MatchingAlgorithm
  public var match: String
  public var isInsensitive: Bool

  // For PermissionsModel conformance
  public var owner: Owner

  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  public var setPermissions: Permissions?

  public init(
    name: String = "",
    path: String = "",
    matchingAlgorithm: MatchingAlgorithm = .none,
    match: String = "",
    isInsensitive: Bool = false,
    owner: Owner = .unset,
    permissions: Permissions? = nil,
    setPermissions: Permissions? = nil
  ) {
    self.name = name
    self.path = path
    self.matchingAlgorithm = matchingAlgorithm
    self.match = match
    self.isInsensitive = isInsensitive
    self.owner = owner
    self.permissions = permissions
    self.setPermissions = setPermissions
  }
}

extension ProtoStoragePath: PermissionsModel {}
