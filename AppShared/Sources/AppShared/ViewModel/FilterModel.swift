//
//  FilterModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.08.23.
//

import DataModel
import Foundation
import Observation
import os

@MainActor
@Observable
public final class FilterModel {
  public var ready: Bool = true

  /// True while the document list has a fill or refresh in flight. Lives here,
  /// next to `ready`, rather than as `@State` on the screen that hosts the list:
  /// a `@State` flip re-evaluates the whole screen — including the glass
  /// safe-area inset above the list — and that layout pass lands exactly while
  /// UIRefreshControl is animating the pull back, which showed as a jump on
  /// release. On an `@Observable` only the search bar's spinner invalidates.
  public var isFetching: Bool = false

  public var filterState: FilterState = {
    Logger.shared.trace("Loading FilterState")
    guard
      let data = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.object(
        forKey: "GlobalFilterState") as? Data
    else {
      Logger.shared.trace("No default")
      return .default
    }
    do {
      let value = try JSONDecoder().decode(FilterState.self, from: data)
      Logger.shared.trace(
        "Decoded filter state from UserDefaults: \(String(decoding: data, as: UTF8.self)) -> \(String(describing: value)) -> "
      )
      return value
    } catch {
      Logger.shared.warning(
        "Decoding filter state from UserDefaults failed: \(String(decoding: data, as: UTF8.self)) -> \(error)"
      )
      return .default
    }
  }()
  {
    didSet {
      Logger.shared.trace("FilterState modified")
      if filterState == oldValue, filterState.modified == oldValue.modified {
        return
      }

      guard let s = try? JSONEncoder().encode(filterState) else {
        Logger.shared.warning(
          "Encoding filter state to UserDefaults failed: \(String(describing: self.filterState))")
        return
      }
      UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.set(
        s, forKey: "GlobalFilterState")

      Logger.shared.trace(
        "Encoded filter state to UserDefaults: \(String(describing: self.filterState)) -> \(String(decoding: s, as: UTF8.self))"
      )
    }
  }

  public init() {
    observeDefaults()
  }

  /// Applies changes to the filtering defaults (made in Preferences) to the
  /// filter that is currently in effect.
  ///
  /// `withObservationTracking` fires once, so the tracking is re-armed after
  /// every change. `onChange` runs *before* the new value is in place, hence
  /// the hop to the next main-actor turn before reading it.
  private func observeDefaults() {
    let settings = AppSettings.shared
    withObservationTracking {
      _ = settings.defaultSearchMode
      _ = settings.defaultSortField
      _ = settings.defaultSortOrder
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.applyDefaults()
        self.observeDefaults()
      }
    }
  }

  private func applyDefaults() {
    let settings = AppSettings.shared
    var filterState = filterState

    if self.filterState.searchText.isEmpty {
      Logger.shared.debug(
        "Applying search mode default change to: \(String(describing: settings.defaultSearchMode), privacy: .public)"
      )
      // User has not typed any search text yet -> we're not changing the mode under them
      filterState.searchMode = settings.defaultSearchMode

      // Reset modified to what it was before, we're not actually modifying anything
      filterState.modified = self.filterState.modified
    }

    if !self.filterState.modified, self.filterState.savedView == nil {
      filterState.sortField = settings.defaultSortField
      filterState.sortOrder = settings.defaultSortOrder
    }

    self.filterState = filterState
  }
}
