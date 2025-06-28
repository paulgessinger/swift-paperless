//
//  FilterModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.08.23.
//

import Combine
import DataModel
import Foundation
import os

@MainActor
class FilterModel: ObservableObject {
    private var tasks = Set<AnyCancellable>()

    var filterStatePublisher =
        PassthroughSubject<FilterState, Never>()

    @Published var ready: Bool = true

    @Published var filterState: FilterState = {
        Logger.shared.trace("Loading FilterState")
        guard let data = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.object(forKey: "GlobalFilterState") as? Data else {
            Logger.shared.trace("No default")
            return .default
        }
        do {
            let value = try JSONDecoder().decode(FilterState.self, from: data)
            Logger.shared.trace("Decoded filter state from UserDefaults: \(String(decoding: data, as: UTF8.self)) -> \(String(describing: value)) -> ")
            return value
        } catch {
            Logger.shared.warning("Decoding filter state from UserDefaults failed: \(String(decoding: data, as: UTF8.self)) -> \(error)")
            return .default
        }
    }() {
        didSet {
            Logger.shared.trace("FilterState modified")
            if filterState == oldValue, filterState.modified == oldValue.modified {
                return
            }

            guard let s = try? JSONEncoder().encode(filterState) else {
                Logger.shared.warning("Encoding filter state to UserDefaults failed: \(String(describing: self.filterState))")
                return
            }
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")?.set(s, forKey: "GlobalFilterState")

            Logger.shared.trace("Encoded filter state to UserDefaults: \(String(describing: self.filterState)) -> \(String(decoding: s, as: UTF8.self))")
        }
    }

    init() {
        $filterState
            .removeDuplicates()
            .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.filterStatePublisher.send(value)
            }
            .store(in: &tasks)

        AppSettings.shared.settingsChanged
            .sink { [weak self] in
                guard let self else { return }

                var filterState = filterState

                if self.filterState.searchText.isEmpty {
                    Logger.shared.debug("Applying search mode default change to: \(String(describing: AppSettings.shared.defaultSearchMode), privacy: .public)")
                    // User has not typed any search text yet -> we're not changing the mode under them
                    filterState.searchMode = AppSettings.shared.defaultSearchMode

                    // Reset modified to what it was before, we're not actually modifying anything
                    filterState.modified = self.filterState.modified
                }

                if !self.filterState.modified, self.filterState.savedView == nil {
                    filterState.sortField = AppSettings.shared.defaultSortField
                    filterState.sortOrder = AppSettings.shared.defaultSortOrder
                }

                self.filterState = filterState
            }
            .store(in: &tasks)
    }
}
