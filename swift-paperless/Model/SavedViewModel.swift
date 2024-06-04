//
//  SavedViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

protocol SavedViewProtocol: Codable {
    var name: String { get set }
    var showOnDashboard: Bool { get set }
    var showInSidebar: Bool { get set }
    var sortField: SortField? { get set }
    var sortOrder: SortOrder { get set }
    var filterRules: [FilterRule] { get set }
}

struct SavedView: Codable, Identifiable, Hashable, Model, SavedViewProtocol {
    var id: UInt
    var name: String
    var showOnDashboard: Bool
    var showInSidebar: Bool
    var sortField: SortField?
    var sortOrder: SortOrder
    var filterRules: [FilterRule]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortOrder = "sort_reverse"
        case filterRules = "filter_rules"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static var localizedName: String { String(localized: .localizable.savedView) }
}

struct ProtoSavedView: Codable, SavedViewProtocol {
    var name: String = ""
    var showOnDashboard: Bool = false
    var showInSidebar: Bool = false
    var sortField: SortField? = .created
    var sortOrder: SortOrder = .descending
    var filterRules: [FilterRule] = []

    private enum CodingKeys: String, CodingKey {
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortOrder = "sort_reverse"
        case filterRules = "filter_rules"
    }
}
