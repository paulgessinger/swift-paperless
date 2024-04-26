//
//  FilterModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.08.23.
//

import Combine
import Foundation
import os

class FilterModel: ObservableObject {
    private var tasks = Set<AnyCancellable>()

    var filterStatePublisher =
        PassthroughSubject<FilterState, Never>()

    @Published var ready: Bool = true

    @Published var filterState: FilterState = {
        Logger.shared.trace("Loading FilterState")
        guard let data = UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.object(forKey: "GlobalFilterState") as? Data else {
            Logger.shared.trace("No default")
            return FilterState()
        }
        do {
            let value = try JSONDecoder().decode(FilterState.self, from: data)
            Logger.shared.trace("Decoded filter state from UserDefaults: \(String(decoding: data, as: UTF8.self)) -> \(String(describing: value)) -> ")
            return value
        } catch {
            Logger.shared.warning("Decoding filter state from UserDefaults failed: \(String(decoding: data, as: UTF8.self)) -> \(error)")
            return FilterState()
        }
    }() {
        didSet {
            Logger.shared.trace("FilterState modified")
            if filterState == oldValue {
                return
            }

            guard let s = try? JSONEncoder().encode(filterState) else {
                Logger.shared.warning("Encoding filter state to UserDefaults failed: \(String(describing: self.filterState))")
                return
            }
            UserDefaults(suiteName: "group.com.paulgessinger.swift-paperless")!.set(s, forKey: "GlobalFilterState")

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
    }
}
