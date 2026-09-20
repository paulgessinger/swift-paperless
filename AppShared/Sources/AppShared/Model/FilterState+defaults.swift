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
      sorting: nil,
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
    sorting = Sorting(
      field: savedView.sortField ?? Self.defaultSortField, order: savedView.sortOrder)
    modified = false  // if we initialize from saved view, it's not modified by definition
  }

  /// Whether the list is sorted the way it usually is — a question about the
  /// values, not about whether the sort is pinned. A pinned sort that matches
  /// the default lights nothing up, because nothing looks different.
  public var hasDefaultSorting: Bool {
    resolvedSorting == Self.defaultSorting
  }

  /// Whether this filter still matches the saved view it was built from.
  ///
  /// Derived rather than latched: undoing an edit reads as unmodified again.
  public func isModified(from savedView: SavedView) -> Bool {
    resolved != FilterState(savedView: savedView).resolved
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
    ruleCount > 0 || !hasDefaultSorting
  }

  public var defaultAwareRuleCount: UInt {
    UInt(ruleCount + (hasDefaultSorting ? 0 : 1))
  }
}
