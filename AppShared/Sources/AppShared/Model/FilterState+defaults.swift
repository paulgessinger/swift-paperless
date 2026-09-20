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

  /// Whether this filter still matches the saved view it was built from.
  ///
  /// Derived rather than latched: undoing an edit reads as unmodified again.
  public func isModified(from savedView: SavedView) -> Bool {
    self != FilterState(savedView: savedView)
  }

  /// Whether this filter differs from the one a fresh list opens with.
  public var isModifiedFromDefault: Bool {
    self != .default
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
