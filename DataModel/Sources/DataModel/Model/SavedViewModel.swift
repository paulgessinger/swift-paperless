//
//  SavedViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation
import MetaCodable

public protocol SavedViewProtocol: Codable {
  var name: String { get set }
  var showOnDashboard: Bool { get set }
  var showInSidebar: Bool { get set }
  var sortField: SortField? { get set }
  var sortOrder: DataModel.SortOrder { get set }
  var filterRules: [FilterRule] { get set }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct SavedView:
  Identifiable, Hashable, Model, SavedViewProtocol, Sendable
{
  public var id: UInt
  public var name: String
  public var showOnDashboard: Bool
  public var showInSidebar: Bool
  public var sortField: SortField?

  @CodedAt("sort_reverse")
  public var sortOrder: DataModel.SortOrder
  public var filterRules: [FilterRule]

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

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
}
