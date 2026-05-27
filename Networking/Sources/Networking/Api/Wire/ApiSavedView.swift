//
//  ApiSavedView.swift
//  Networking
//

import DataModel

// MARK: - Wire type for reading saved views
//
// `filter_rules: [FilterRule]`, `owner: Owner?`, `permissions: Permissions?`
// embed leaf wire-symmetric value types straight from DataModel — see the
// Stage 3 plan for the rule. Each domain type carries its own JSON shape and
// is round-tripped as-is.

struct ApiSavedView: Codable, Sendable {
  var id: UInt
  var name: String
  // Backends >= v3.0 omit show_on_dashboard / show_in_sidebar; both default
  // to false at the domain layer.
  var show_on_dashboard: Bool?
  var show_in_sidebar: Bool?
  // `null` or absent in JSON decodes to a Swift `nil` (no SortField); the
  // domain still carries `Optional<SortField>`.
  var sort_field: SortField?
  var sort_reverse: Bool
  var filter_rules: [FilterRule]
  // `owner: null` (Owner's own decoder maps null → .none) and `owner` absent
  // both surface here as `nil`, which the domain maps to `Owner.unset`.
  var owner: Owner?
  var permissions: Permissions?
  var user_can_change: Bool?
}

extension ApiSavedView {
  var domain: SavedView {
    var view = SavedView(
      id: id,
      name: name,
      showOnDashboard: show_on_dashboard ?? false,
      showInSidebar: show_in_sidebar ?? false,
      sortField: sort_field,
      sortOrder: DataModel.SortOrder(sort_reverse),
      filterRules: filter_rules,
      owner: owner ?? .unset,
      userCanChange: user_can_change ?? true
    )
    view.permissions = permissions
    return view
  }
}

// MARK: - Wire type for creating saved views

struct ApiSavedViewCreate: Encodable, Sendable {
  var name: String
  var show_on_dashboard: Bool
  var show_in_sidebar: Bool
  var sort_field: SortField?
  var sort_reverse: Bool
  var filter_rules: [FilterRule]
  var owner: Owner
  var set_permissions: Permissions?
}

extension ApiSavedViewCreate {
  init(from proto: ProtoSavedView) {
    self.init(
      name: proto.name,
      show_on_dashboard: proto.showOnDashboard,
      show_in_sidebar: proto.showInSidebar,
      sort_field: proto.sortField,
      sort_reverse: proto.sortOrder.reverse,
      filter_rules: proto.filterRules,
      owner: proto.owner,
      set_permissions: proto.permissions
    )
  }
}

// MARK: - Wire type for updating saved views

struct ApiSavedViewUpdate: Encodable, Sendable {
  var id: UInt
  var name: String
  var show_on_dashboard: Bool
  var show_in_sidebar: Bool
  var sort_field: SortField?
  var sort_reverse: Bool
  var filter_rules: [FilterRule]
  var owner: Owner
  var set_permissions: Permissions?
}

extension ApiSavedViewUpdate {
  init(from view: SavedView) {
    self.init(
      id: view.id,
      name: view.name,
      show_on_dashboard: view.showOnDashboard,
      show_in_sidebar: view.showInSidebar,
      sort_field: view.sortField,
      sort_reverse: view.sortOrder.reverse,
      filter_rules: view.filterRules,
      owner: view.owner,
      set_permissions: view.permissions
    )
  }
}
