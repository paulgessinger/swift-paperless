//
//  SavedViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation
import MetaCodable

public protocol SavedViewProtocol: Codable, PermissionsModel {
  var name: String { get set }
  var showOnDashboard: Bool { get set }
  var showInSidebar: Bool { get set }
  var sortField: SortField? { get set }
  var sortOrder: DataModel.SortOrder { get set }
  var filterRules: [FilterRule] { get set }
  var userCanChange: Bool { get }
}

extension SavedViewProtocol {
  public var userCanChange: Bool { true }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct SavedView:
  Identifiable, Hashable, Model, SavedViewProtocol, Sendable
{
  public var id: UInt
  public var name: String

  @Default(false)
  public var showOnDashboard: Bool

  @Default(false)
  public var showInSidebar: Bool

  public var sortField: SortField?

  @CodedAt("sort_reverse")
  public var sortOrder: DataModel.SortOrder
  public var filterRules: [FilterRule]

  @Default(Owner.unset)
  public var owner: Owner

  // Presence of this depends on the endpoint
  @IgnoreEncoding
  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  // The API wants this extra key for writing perms
  public var setPermissions: Permissions?

  @IgnoreEncoding
  @Default(true)
  public var userCanChange: Bool

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension SavedView: PermissionsModel {}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ProtoSavedView: SavedViewProtocol, Sendable {
  @Default("")
  public var name: String

  @Default(false)
  public var showOnDashboard: Bool

  @Default(false)
  public var showInSidebar: Bool

  @Default(SortField.created)
  public var sortField: SortField?

  @CodedAt("sort_reverse")
  @Default(DataModel.SortOrder.descending)
  public var sortOrder: DataModel.SortOrder

  @Default([FilterRule]())
  public var filterRules: [FilterRule]

  // For PermissionsModel conformance
  @Default(Owner.unset)
  public var owner: Owner

  // Presence of this depends on the endpoint
  @IgnoreEncoding
  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  // The API wants this extra key for writing perms
  public var setPermissions: Permissions?
}

extension ProtoSavedView: PermissionsModel {}
