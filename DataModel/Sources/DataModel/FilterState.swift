//
//  FilterState.swift
//  DataModel
//
//  Created by Paul Gessinger on 09.03.25.
//

import Common
import os

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

    // MARK: Methods

    public mutating func handleElementAny(ids: [UInt]?, filter: Filter,
                                          rule: FilterRule) -> Filter
    {
        guard let ids else {
            Logger.dataModel.error("Invalid value for rule type or nil id \(String(describing: rule.ruleType)), \(String(describing: rule.value))")
            remaining.append(rule)
            return filter
        }

        switch filter {
        case let .anyOf(existing):
            return .anyOf(ids: existing + ids)
        case .noneOf:
            Logger.dataModel.notice("Rule set combination invalid: anyOf + noneOf")
            fallthrough
        default:
            return .anyOf(ids: ids)
        }
    }

    public mutating func handleElementNone(ids: [UInt]?, filter: Filter, rule: FilterRule) -> Filter {
        guard let ids else {
            Logger.dataModel.error("Invalid value for rule type or nil id \(String(describing: rule.ruleType)), \(String(describing: rule.value))")
            remaining.append(rule)
            return filter
        }

        switch filter {
        case let .noneOf(existing):
            return .noneOf(ids: existing + ids)
        case .anyOf:
            Logger.dataModel.notice("Rule set combination invalid: anyOf + noneOf")
            fallthrough
        default:
            return .noneOf(ids: ids)
        }
    }

    public var rules: [FilterRule] {
        var result = remaining

        if !searchText.isEmpty {
            result.append(
                .init(ruleType: searchMode.ruleType, value: .string(value: searchText))
            )
        }

        switch correspondent {
        case .notAssigned:
            result.append(
                .init(ruleType: .correspondent, value: .correspondent(id: nil))
            )
        case let .anyOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .hasCorrespondentAny, value: .correspondent(id: id))
                )
            }
        case let .noneOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: id))
                )
            }
        case .any: break
        }

        switch documentType {
        case .notAssigned:
            result.append(
                .init(ruleType: .documentType, value: .documentType(id: nil))
            )
        case let .anyOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .hasDocumentTypeAny, value: .documentType(id: id))
                )
            }
        case let .noneOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .doesNotHaveDocumentType, value: .documentType(id: id))
                )
            }
        case .any: break
        }

        switch storagePath {
        case .notAssigned:
            result.append(
                .init(ruleType: .storagePath, value: .storagePath(id: nil)))
        case let .anyOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .hasStoragePathAny, value: .storagePath(id: id)))
            }
        case let .noneOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: id)))
            }
        case .any: break
        }

        switch tags {
        case .any: break
        case .notAssigned:
            result.append(
                .init(ruleType: .hasAnyTag, value: .boolean(value: false))
            )
        case let .allOf(include, exclude):
            for id in include {
                result.append(
                    .init(ruleType: .hasTagsAll, value: .tag(id: id)))
            }
            for id in exclude {
                result.append(
                    .init(ruleType: .doesNotHaveTag, value: .tag(id: id)))
            }
        case let .anyOf(ids):
            for id in ids {
                result.append(
                    .init(ruleType: .hasTagsAny, value: .tag(id: id)))
            }
        }

        switch owner {
        case .any: break
        case .notAssigned:
            result.append(
                .init(ruleType: .ownerIsnull, value: .boolean(value: true))
            )
        case let .anyOf(ids):
            for id in ids {
                result.append(.init(ruleType: .ownerAny, value: .number(value: Int(id))))
            }
        case let .noneOf(ids):
            for id in ids {
                result.append(.init(ruleType: .ownerDoesNotInclude, value: .number(value: Int(id))))
            }
        }

        return result
    }

    public var ruleCount: Int {
        var result = 0
        if documentType != .any {
            result += 1
        }
        if correspondent != .any {
            result += 1
        }
        if storagePath != .any {
            result += 1
        }
        if owner != .any {
            result += 1
        }
        if tags != .any {
            result += 1
        }
        if !searchText.isEmpty {
            result += 1
        }

        return result
    }
}
