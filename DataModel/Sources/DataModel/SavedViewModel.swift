//
//  SavedViewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

public protocol SavedViewProtocol: Codable {
    var name: String { get set }
    var showOnDashboard: Bool { get set }
    var showInSidebar: Bool { get set }
    var sortField: SortField? { get set }
    var sortOrder: DataModel.SortOrder { get set }
    var filterRules: [FilterRule] { get set }
}

public struct SavedView:
    Codable, Identifiable, Hashable, Model, SavedViewProtocol, Sendable
{
    public var id: UInt
    public var name: String
    public var showOnDashboard: Bool
    public var showInSidebar: Bool
    public var sortField: SortField?
    public var sortOrder: DataModel.SortOrder
    public var filterRules: [FilterRule]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortOrder = "sort_reverse"
        case filterRules = "filter_rules"
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct ProtoSavedView: Codable, SavedViewProtocol, Sendable {
    public var name: String
    public var showOnDashboard: Bool
    public var showInSidebar: Bool
    public var sortField: SortField?
    public var sortOrder: DataModel.SortOrder
    public var filterRules: [FilterRule]

    public init(name: String = "", showOnDashboard: Bool = false, showInSidebar: Bool = false, sortField: SortField? = .created, sortOrder: DataModel.SortOrder = .descending, filterRules: [FilterRule] = []) {
        self.name = name
        self.showOnDashboard = showOnDashboard
        self.showInSidebar = showInSidebar
        self.sortField = sortField
        self.sortOrder = sortOrder
        self.filterRules = filterRules
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case showOnDashboard = "show_on_dashboard"
        case showInSidebar = "show_in_sidebar"
        case sortField = "sort_field"
        case sortOrder = "sort_reverse"
        case filterRules = "filter_rules"
    }
}
