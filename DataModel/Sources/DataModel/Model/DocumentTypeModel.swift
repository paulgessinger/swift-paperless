//
//  DocumentTypeModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

public protocol DocumentTypeProtocol: Equatable, MatchingModel {
  var name: String { get set }
}

public struct DocumentType:
  Hashable,
  Identifiable,
  Model,
  DocumentTypeProtocol,
  Named,
  Sendable
{
  public var id: UInt
  public var name: String
  public var slug: String

  public var match: String
  public var matchingAlgorithm: MatchingAlgorithm
  public var isInsensitive: Bool

  public init(
    id: UInt,
    name: String,
    slug: String,
    match: String,
    matchingAlgorithm: MatchingAlgorithm,
    isInsensitive: Bool
  ) {
    self.id = id
    self.name = name
    self.slug = slug
    self.match = match
    self.matchingAlgorithm = matchingAlgorithm
    self.isInsensitive = isInsensitive
  }
}

public struct ProtoDocumentType: Hashable, DocumentTypeProtocol, Sendable {
  public var name: String
  public var match: String
  public var matchingAlgorithm: MatchingAlgorithm
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
    match: String = "",
    matchingAlgorithm: MatchingAlgorithm = .auto,
    isInsensitive: Bool = false,
    owner: Owner = .unset,
    permissions: Permissions? = nil,
    setPermissions: Permissions? = nil
  ) {
    self.name = name
    self.match = match
    self.matchingAlgorithm = matchingAlgorithm
    self.isInsensitive = isInsensitive
    self.owner = owner
    self.permissions = permissions
    self.setPermissions = setPermissions
  }
}

extension ProtoDocumentType: PermissionsModel {}
