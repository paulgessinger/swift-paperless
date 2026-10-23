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

  /// The filter the document list opens with: the last one in effect, or the
  /// default when there is none.
  ///
  /// Also read by the *Recently browsed* cap, which runs just before the list
  /// opens and leaves this filter's list whole rather than cutting what the
  /// list's fill is about to download again.
  public nonisolated static func restoredFilterState() -> FilterState {
    Logger.shared.trace("Loading FilterState")
    guard
      let data = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.object(
        forKey: "GlobalFilterState") as? Data
    else {
      Logger.shared.trace("No default")
      return .default
    }
    do {
      var value = try JSONDecoder().decode(FilterState.self, from: data)
      value.adoptLegacySorting(fromPersisted: data)
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
  }

  /// The local view the list opened on last, if it was one.
  public nonisolated static func restoredLocalView() -> LocalView? {
    UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?
      .string(forKey: "GlobalLocalView").flatMap(LocalView.init(rawValue:))
  }

  /// The local view on screen in place of `filterState`'s query, if any.
  /// `filterState` keeps the user's filter meanwhile, for when they leave it.
  public var localView: LocalView? = FilterModel.restoredLocalView() {
    didSet {
      guard localView != oldValue else { return }
      UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.set(
        localView?.rawValue, forKey: "GlobalLocalView")
    }
  }

  /// The local view whose documents the list shows. It trails `localView`
  /// while the list animates to the new rows, and the filter bar follows it,
  /// so the inset above the list changes only once the rows have moved.
  public var displayedLocalView: LocalView? = FilterModel.restoredLocalView()

  public var filterState: FilterState = FilterModel.restoredFilterState()
  {
    didSet {
      Logger.shared.trace("FilterState modified")
      if filterState == oldValue {
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

  /// The app-default sort, mirrored here so that a change to it is observable.
  ///
  /// `FilterState` resolves the default through `SettingsStore`, which is
  /// deliberately not observable (it is nonisolated, so `FilterState.default`
  /// can read it). A filter that follows the default is therefore *unchanged*
  /// when Preferences moves it, and anything keyed on the filter alone would
  /// never re-query.
  public private(set) var defaultSorting: FilterState.Sorting = FilterState.defaultSorting

  /// The filter as the document list should run it: the live filter with its
  /// sort pinned to whatever it resolves to. This is the value to observe —
  /// see ``defaultSorting``.
  public var resolvedFilterState: FilterState {
    var state = filterState
    state.sorting = filterState.sorting ?? defaultSorting
    return state
  }

  /// What the document list shows. A filter change under a local view leaves
  /// it as it is.
  public var listSource: DocumentListSource {
    localView.map(DocumentListSource.local) ?? .query(resolvedFilterState)
  }

  /// Leaves any local view for the documents `filter` selects.
  public func show(_ filter: FilterState) {
    localView = nil
    filterState = filter
  }

  /// Leaves any local view for the default list.
  public func clear() {
    show(.default)
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

    // The sort needs no pass of its own: a filter that has not picked one
    // stores `nil` and resolves against the default on every read. Mirroring
    // it into `defaultSorting` is what lets the list notice.
    defaultSorting = FilterState.defaultSorting

    if filterState.searchText.isEmpty {
      Logger.shared.debug(
        "Applying search mode default change to: \(String(describing: settings.defaultSearchMode), privacy: .public)"
      )
      // User has not typed any search text yet -> we're not changing the mode under them
      filterState.searchMode = settings.defaultSearchMode
    }
  }
}
