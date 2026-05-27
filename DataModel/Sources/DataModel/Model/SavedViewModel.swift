//
//  SavedViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

public protocol SavedViewProtocol: PermissionsModel {
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

public struct SavedView:
  Identifiable, Hashable, Model, SavedViewProtocol, Sendable
{
  public var id: UInt
  public var name: String
  public var showOnDashboard: Bool
  public var showInSidebar: Bool
  public var sortField: SortField?
  public var sortOrder: DataModel.SortOrder
  public var filterRules: [FilterRule]
  public var owner: Owner

  public var permissions: Permissions? {
    didSet {
      setPermissions = permissions
    }
  }

  public var setPermissions: Permissions?
  public var userCanChange: Bool

  public init(
    id: UInt,
    name: String,
    showOnDashboard: Bool = false,
    showInSidebar: Bool = false,
    sortField: SortField? = nil,
    sortOrder: DataModel.SortOrder = .descending,
    filterRules: [FilterRule] = [],
    owner: Owner = .unset,
    permissions: Permissions? = nil,
    setPermissions: Permissions? = nil,
    userCanChange: Bool = true
  ) {
    self.id = id
    self.name = name
    self.showOnDashboard = showOnDashboard
    self.showInSidebar = showInSidebar
    self.sortField = sortField
    self.sortOrder = sortOrder
    self.filterRules = filterRules
    self.owner = owner
    self.permissions = permissions
    self.setPermissions = setPermissions
    self.userCanChange = userCanChange
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

extension SavedView: PermissionsModel {}

public struct ProtoSavedView: SavedViewProtocol, Sendable {
  public var name: String
  public var showOnDashboard: Bool
  public var showInSidebar: Bool
  public var sortField: SortField?
  public var sortOrder: DataModel.SortOrder
  public var filterRules: [FilterRule]

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
    showOnDashboard: Bool = false,
    showInSidebar: Bool = false,
    sortField: SortField? = .created,
    sortOrder: DataModel.SortOrder = .descending,
    filterRules: [FilterRule] = [],
    owner: Owner = .unset,
    permissions: Permissions? = nil,
    setPermissions: Permissions? = nil
  ) {
    self.name = name
    self.showOnDashboard = showOnDashboard
    self.showInSidebar = showInSidebar
    self.sortField = sortField
    self.sortOrder = sortOrder
    self.filterRules = filterRules
    self.owner = owner
    self.permissions = permissions
    self.setPermissions = setPermissions
  }
}

extension ProtoSavedView: PermissionsModel {}
