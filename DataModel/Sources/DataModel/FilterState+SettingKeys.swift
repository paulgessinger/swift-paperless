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
}
