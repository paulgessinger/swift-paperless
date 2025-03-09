//
//  FilterState.swift
//  DataModel
//
//  Created by Paul Gessinger on 09.03.25.
//

import Common

public struct FilterState: Equatable, Codable, Sendable {
    public enum Filter: Equatable, Hashable, Codable, Sendable {
        case any
        case notAssigned
        case anyOf(ids: [UInt])
        case noneOf(ids: [UInt])
    }

    public enum TagFilter: Equatable, Hashable, Codable, Sendable {
        case any
        case notAssigned
        case allOf(include: [UInt], exclude: [UInt])
        case anyOf(ids: [UInt])
    }

    public enum SearchMode: Equatable, Codable, CaseIterable, Sendable {
        case title
        case content
        case titleContent
        case advanced

        public var ruleType: FilterRuleType {
            switch self {
            case .title:
                .title
            case .content:
                .content
            case .titleContent:
                .titleContent
            case .advanced:
                .fulltextQuery
            }
        }

        public init?(ruleType: FilterRuleType) {
            switch ruleType {
            case .title:
                self = .title
            case .content:
                self = .content
            case .titleContent:
                self = .titleContent
            case .fulltextQuery:
                self = .advanced
            default:
                return nil
            }
        }
    }

    public var correspondent: Filter = .any { didSet { modified = modified || correspondent != oldValue }}
    public var documentType: Filter = .any { didSet { modified = modified || documentType != oldValue }}
    public var storagePath: Filter = .any { didSet { modified = modified || storagePath != oldValue }}
    public var owner: Filter = .any { didSet { modified = modified || owner != oldValue } }

    public var tags: TagFilter = .any { didSet { modified = modified || tags != oldValue }}
    public var remaining: [FilterRule] = [] { didSet { modified = modified || remaining != oldValue }}

    public var sortField: SortField {
        didSet { modified = modified || sortField != oldValue }
    }

    public var sortOrder: DataModel.SortOrder {
        didSet { modified = modified || sortOrder != oldValue }
    }

    public var savedView: UInt? = nil

    @EquatableNoop
    public var modified = false

    public var searchText: String = "" {
        didSet {
            modified = modified || searchText != oldValue
        }
    }

    public var searchMode: SearchMode {
        didSet { modified = searchMode != oldValue }
    }

    public init(correspondent: Filter,
                documentType: Filter,
                storagePath: Filter,
                owner: Filter,
                tags: TagFilter,
                sortField: SortField,
                sortOrder: DataModel.SortOrder,
                remaining: [FilterRule],
                savedView: UInt?,
                searchText: String?,
                searchMode: SearchMode)
    {
        self.correspondent = correspondent
        self.documentType = documentType
        self.storagePath = storagePath
        self.owner = owner
        self.tags = tags
        self.sortField = sortField
        self.sortOrder = sortOrder
        self.remaining = remaining
        self.savedView = savedView
        self.searchText = searchText ?? ""
        self.searchMode = searchMode
    }
}
