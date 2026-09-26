//
//  FilterState+SettingKeys.swift
//  DataModel
//

import Common
import Foundation

// The filtering defaults, declared next to the types they carry so that
// FilterState can resolve them without reaching up into the app layer. The
// name is the key the value is stored under: it is persisted user data, so
// renaming one orphans what users already have stored.
extension SettingKey {
  public static var defaultSearchMode: SettingKey<FilterState.SearchMode> {
    .init("defaultSearchMode", default: .titleContent)
  }

  public static var defaultSortField: SettingKey<SortField> {
    .init("defaultSortField", default: .added)
  }

  public static var defaultSortOrder: SettingKey<DataModel.SortOrder> {
    .init("defaultSortOrder", default: .descending)
  }
}

extension FilterState {
  // Read straight from the store rather than through AppSettings: these are
  // nonisolated, and the store shares one cache and one set of defaults with
  // the main-actor settings object.
  public static var defaultSearchMode: SearchMode {
    SettingsStore.shared[.defaultSearchMode]
  }

  public static var defaultSortField: SortField {
    SettingsStore.shared[.defaultSortField]
  }

  public static var defaultSortOrder: DataModel.SortOrder {
    SettingsStore.shared[.defaultSortOrder]
  }

  /// The sort a filter follows when it has not picked one.
  public static var defaultSorting: Sorting {
    Sorting(field: defaultSortField, order: defaultSortOrder)
  }

  /// ``sorting``, or the app default when the filter follows it.
  public var resolvedSorting: Sorting {
    sorting ?? Self.defaultSorting
  }

  /// Carries over a sort from a payload written before ``sorting`` became
  /// nullable, where the pair was stored as `sortField` / `sortOrder`.
  ///
  /// A legacy sort equal to the defaults in force is taken as one the user
  /// never picked, so it goes on following them; anything else is pinned,
  /// which is how it already behaved. Idempotent: a payload written since
  /// carries no legacy keys.
  public mutating func adoptLegacySorting(fromPersisted data: Data) {
    guard sorting == nil,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let rawField = object["sortField"] as? String,
      let field = SortField(rawValue: rawField),
      let reverse = object["sortOrder"] as? Bool
    else { return }

    let legacy = Sorting(field: field, order: .init(reverse))
    guard legacy != Self.defaultSorting else { return }
    sorting = legacy
  }

  /// This filter with its sort pinned to what it resolves to right now, and
  /// its ID selections in a canonical order.
  ///
  /// Two filters address the same list when their resolved forms match, so
  /// this is the form to compare when the question is "same query?" rather
  /// than "same user intent?". The pickers append a reselected ID, so
  /// selection order is intent, not query.
  public var resolved: FilterState {
    var copy = self
    copy.sorting = resolvedSorting
    copy.correspondent = correspondent.canonicalized
    copy.documentType = documentType.canonicalized
    copy.storagePath = storagePath.canonicalized
    copy.owner = owner.canonicalized
    copy.tags = tags.canonicalized
    return copy
  }
}

extension FilterState.Filter {
  fileprivate var canonicalized: Self {
    switch self {
    case .any, .notAssigned: self
    case .anyOf(let ids): .anyOf(ids: ids.sorted())
    case .noneOf(let ids): .noneOf(ids: ids.sorted())
    }
  }
}

extension FilterState.TagFilter {
  fileprivate var canonicalized: Self {
    switch self {
    case .any, .notAssigned: self
    case .allOf(let include, let exclude):
      .allOf(include: include.sorted(), exclude: exclude.sorted())
    case .anyOf(let ids): .anyOf(ids: ids.sorted())
    }
  }
}
