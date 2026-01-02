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
  private static var defaultSearchMode: SearchMode {
    AppSettings.value(for: .defaultSearchMode, or: .titleContent)
  }

  private static var defaultSortField: SortField {
    AppSettings.value(for: .defaultSortField, or: .added)
  }

  private static var defaultSortOrder: DataModel.SortOrder {
    AppSettings.value(for: .defaultSortOrder, or: .descending)
  }

  // MARK: Initializers

  static var `default`: Self {
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

  init(savedView: SavedView) {
    self = Self.create(using: \.default, withRules: savedView.filterRules)
    self.savedView = savedView.id
    if let sortField = savedView.sortField {
      self.sortField = sortField
    }
    sortOrder = savedView.sortOrder
    modified = false  // if we initialize from saved view, it's not modified by definition
  }

  var defaultSorting: Bool {
    sortField == Self.defaultSortField && sortOrder == Self.defaultSortOrder
  }

  // MARK: Methods

  mutating func clear() {
    self = FilterState.default
  }

  var filtering: Bool {
    ruleCount > 0 || !defaultSorting
  }
}
