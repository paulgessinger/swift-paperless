//
//  FilterState+defaults.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.12.2024.
//

import Common
import DataModel
import Foundation
import os

// MARK: - FilterState

extension FilterState {
  // Read straight from the store rather than through AppSettings: this is
  // nonisolated, and the store shares one cache and one set of defaults with
  // the main-actor settings object.
  private static var defaultSearchMode: SearchMode {
    SettingsStore.shared[.defaultSearchMode]
  }

  private static var defaultSortField: SortField {
    SettingsStore.shared[.defaultSortField]
  }

  private static var defaultSortOrder: DataModel.SortOrder {
    SettingsStore.shared[.defaultSortOrder]
  }

  // MARK: Initializers

  public static var `default`: Self {
    Self(
      correspondent: .any,
      documentType: .any,
      storagePath: .any,
      owner: .any,
      tags: .any,
      sortField: defaultSortField,
      sortOrder: defaultSortOrder,
      remaining: [],
      savedView: nil,
      searchText: nil,
      searchMode: defaultSearchMode,
      customField: .any,
      asn: .any
    )
  }

  public init(savedView: SavedView) {
    self = Self.create(using: \.default, withRules: savedView.filterRules)
    self.savedView = savedView.id
    if let sortField = savedView.sortField {
      self.sortField = sortField
    }
    sortOrder = savedView.sortOrder
    modified = false  // if we initialize from saved view, it's not modified by definition
  }

  public var defaultSorting: Bool {
    sortField == Self.defaultSortField && sortOrder == Self.defaultSortOrder
  }

  // MARK: Methods

  public mutating func clear() {
    self = FilterState.default
  }

  public var filtering: Bool {
    ruleCount > 0 || !defaultSorting
  }

  public var defaultAwareRuleCount: UInt {
    UInt(ruleCount + (defaultSorting ? 0 : 1))
  }
}
