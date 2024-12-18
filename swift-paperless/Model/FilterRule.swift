//
//  FilterRule.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.04.23.
//

import DataModel
import Foundation
import os

extension FilterRuleType: Codable {}

enum FilterRuleValue: Codable, Equatable {
    case date(value: Date)
    case number(value: Int)
    case tag(id: UInt)
    case boolean(value: Bool)
    case documentType(id: UInt?)
    case storagePath(id: UInt?)
    case correspondent(id: UInt?)
    case owner(id: UInt?)
    case string(value: String)
    case invalid(value: String)

    fileprivate func string() -> String? {
        var s: String? = nil
        switch self {
        case let .date(value):
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            s = dateFormatter.string(from: value)
        case let .number(value):
            s = String(value)
        case let .tag(id):
            s = String(id)
        case let .boolean(value):
            s = String(value)
        case let .documentType(id):
            s = id == nil ? nil : String(id!)
        case let .storagePath(id):
            s = id == nil ? nil : String(id!)
        case let .correspondent(id):
            s = id == nil ? nil : String(id!)
        case let .owner(id):
            s = id == nil ? nil : String(id!)
        case let .string(value):
            s = value
        case let .invalid(value):
            s = value
        }
        return s
    }

    var correspondentId: [UInt]? {
        switch self {
        case let .correspondent(id):
            if let id {
                [id]
            } else {
                nil
            }
        case let .invalid(value):
            value.components(separatedBy: ",").compactMap { UInt($0) }
        default:
            nil
        }
    }

    var documentTypeId: [UInt]? {
        switch self {
        case let .documentType(id):
            if let id {
                [id]
            } else {
                nil
            }
        case let .invalid(value):
            value.components(separatedBy: ",").compactMap { UInt($0) }
        default:
            nil
        }
    }

    var storagePathId: [UInt]? {
        switch self {
        case let .storagePath(id):
            if let id {
                [id]
            } else {
                nil
            }
        case let .invalid(value):
            value.components(separatedBy: ",").compactMap { UInt($0) }
        default:
            nil
        }
    }
}

private extension KeyedDecodingContainerProtocol {
    func decodeOrConvertOptional<T>(_ type: T.Type, forKey key: Self.Key) throws -> T? where T: Decodable, T: LosslessStringConvertible {
        if let value = try? decode(type, forKey: key) {
            return value
        }
        guard let s = try decode(String?.self, forKey: key) else {
            return nil
        }
        guard let value = T(s) else {
            throw DecodingError.typeMismatch(type, .init(codingPath: [key], debugDescription: "Could not be converted from string"))
        }
        return value
    }

    func decodeOrConvert<T>(_ type: T.Type, forKey key: Self.Key) throws -> T where T: Decodable, T: LosslessStringConvertible {
        guard let value = try decodeOrConvertOptional(type, forKey: key) else {
            throw DecodingError.typeMismatch(type, .init(codingPath: [key], debugDescription: "Nil value but no nullable value expected"))
        }
        return value
    }
}

struct FilterRule: Equatable {
    var ruleType: FilterRuleType
    var value: FilterRuleValue

    init(ruleType: FilterRuleType, value: FilterRuleValue) {
        self.ruleType = ruleType
        self.value = value

        let dt = self.ruleType.dataType()

        switch value {
        case .date:
            precondition(dt == .date, "Invalid data type")
        case .number:
            precondition(dt == .number, "Invalid data type")
        case .tag:
            precondition(dt == .tag, "Invalid data type")
        case .boolean:
            precondition(dt == .boolean, "Invalid data type")
        case .documentType:
            precondition(dt == .documentType, "Invalid data type")
        case .storagePath:
            precondition(dt == .storagePath, "Invalid data type")
        case .correspondent:
            precondition(dt == .correspondent, "Invalid data type")
        case .owner:
            precondition(dt == .number, "Invalid data type")
        case .string:
            precondition(dt == .string, "Invalid data type")
        case .invalid:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ruleType = "rule_type"
        case value
    }

    static func queryItems(for rules: [FilterRule]) -> [URLQueryItem] {
        var result: [URLQueryItem] = []

        let rulesMultiple = rules.filter { $0.ruleType.multiple() }

        let groups = Dictionary(grouping: rulesMultiple, by: { $0.ruleType })

        for (type, group) in groups {
            let values = group.compactMap { $0.value.string() }.sorted()

            if let filterVar = type.filterVar() {
                result.append(.init(name: filterVar, value: values.joined(separator: ",")))
            } else {
                Logger.shared.warning("Unable to add query item for \(String(reflecting: type), privacy: .public)")
            }
        }

        for rule in rules.filter({ !$0.ruleType.multiple() }) {
            guard let filterVar = rule.ruleType.filterVar() else {
                Logger.shared.warning("Unable to add query item for \(String(reflecting: rule.ruleType), privacy: .public)")
                continue
            }

            if case let .boolean(value) = rule.value {
                result.append(.init(name: filterVar, value: value ? "1" : "0"))
            } else if let value = rule.value.string() {
                result.append(.init(name: filterVar, value: value))
            } else {
                guard let nullVar = rule.ruleType.isNullFilterVar() else {
                    fatalError("Rule value is null, but rule has no null filter var")
                }
                result.append(.init(name: nullVar, value: "1"))
            }
        }

        return result
    }
}

extension FilterRule: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleType = try container.decode(FilterRuleType.self, forKey: .ruleType)

        do {
            switch ruleType.dataType() {
            case .date:
                let dateStr = try container.decode(String.self, forKey: .value)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
                guard let date = dateFormatter.date(from: dateStr) else {
                    Logger.shared.error("Unable to decode filter rule date string: \(dateStr, privacy: .public)")
                    throw DateDecodingError.invalidDate(string: dateStr)
                }
                value = .date(value: date)
            case .number:
                value = try .number(value: container.decodeOrConvert(Int.self, forKey: .value))
            case .tag:
                value = try .tag(id: container.decodeOrConvert(UInt.self, forKey: .value))
            case .boolean:
                value = try .boolean(value: container.decodeOrConvert(Bool.self, forKey: .value))
            case .documentType:
                value = try .documentType(id: container.decodeOrConvertOptional(UInt.self, forKey: .value))
            case .storagePath:
                value = try .storagePath(id: container.decodeOrConvertOptional(UInt.self, forKey: .value))
            case .correspondent:
                value = try .correspondent(id: container.decodeOrConvertOptional(UInt.self, forKey: .value))
            case .string:
                value = try .string(value: container.decodeOrConvert(String.self, forKey: .value))
            }
        } catch DecodingError.typeMismatch {
            value = try .invalid(value: container.decodeOrConvert(String.self, forKey: .value))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(ruleType, forKey: .ruleType)

        try container.encode(value.string(), forKey: .value)
    }
}

// MARK: - FilterState

struct FilterState: Equatable, Codable, Sendable {
    enum Filter: Equatable, Hashable, Codable {
        case any
        case notAssigned
        case anyOf(ids: [UInt])
        case noneOf(ids: [UInt])
    }

    enum TagFilter: Equatable, Hashable, Codable {
        case any
        case notAssigned
        case allOf(include: [UInt], exclude: [UInt])
        case anyOf(ids: [UInt])
    }

    enum SearchMode: Equatable, Codable, CaseIterable {
        case title
        case content
        case titleContent
        case advanced

        var ruleType: FilterRuleType {
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

        init?(ruleType: FilterRuleType) {
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

        var localizedName: String {
            switch self {
            case .title:
                String(localized: .localizable(.searchTitle))
            case .content:
                String(localized: .localizable(.searchContent))
            case .titleContent:
                String(localized: .localizable(.searchTitleContent))
            case .advanced:
                String(localized: .localizable(.searchAdvanced))
            }
        }
    }

    var correspondent: Filter = .any { didSet { modified = modified || correspondent != oldValue }}
    var documentType: Filter = .any { didSet { modified = modified || documentType != oldValue }}
    var storagePath: Filter = .any { didSet { modified = modified || storagePath != oldValue }}
    var owner: Filter = .any { didSet { modified = modified || owner != oldValue } }

    var tags: TagFilter = .any { didSet { modified = modified || tags != oldValue }}
    var remaining: [FilterRule] = [] { didSet { modified = modified || remaining != oldValue }}

    var sortField: SortField = AppSettings.value(for: .defaultSortField, or: .added) {
        didSet { modified = modified || sortField != oldValue }
    }

    var sortOrder: DataModel.SortOrder = AppSettings.value(for: .defaultSortOrder, or: .descending) {
        didSet { modified = modified || sortOrder != oldValue }
    }

    var defaultSorting: Bool {
        sortField == AppSettings.value(for: .defaultSortField, or: .added) && sortOrder == AppSettings.value(for: .defaultSortOrder, or: .descending)
    }

    var savedView: UInt? = nil

    @EquatableNoop
    var modified = false

    var searchText: String = "" {
        didSet {
            modified = modified || searchText != oldValue
        }
    }

    var searchMode = AppSettings.value(for: .defaultSearchMode, or: SearchMode.titleContent) {
        didSet { modified = searchMode != oldValue }
    }

    // MARK: Initializers

    init(correspondent: Filter = .any,
         documentType: Filter = .any,
         storagePath: Filter = .any,
         owner: Filter = .any,
         tags: TagFilter = .any,
         remaining: [FilterRule] = [],
         savedView: UInt? = nil,
         searchText: String? = nil,
         searchMode: SearchMode = AppSettings.value(for: .defaultSearchMode, or: .titleContent))
    {
        self.correspondent = correspondent
        self.documentType = documentType
        self.storagePath = storagePath
        self.owner = owner
        self.tags = tags
        self.remaining = remaining
        self.savedView = savedView
        self.searchText = searchText ?? ""
        self.searchMode = searchMode
    }

    init(savedView: SavedView) {
        self.init(rules: savedView.filterRules)
        self.savedView = savedView.id
        self.sortField = savedView.sortField
        self.sortOrder = savedView.sortOrder
    }

    init(rules: [FilterRule]) {
        let getTagIds = { (rule: FilterRule) -> [UInt]? in
            switch rule.value {
            case let .tag(id):
                return [id]
            case let .invalid(value):
                Logger.shared.warning("Recovering multi-value rule \(String(describing: rule.ruleType), privacy: .public) from value \(String(describing: value), privacy: .public)")
                return value.components(separatedBy: ",").compactMap { UInt($0) }
            default:
                return nil
            }
        }

        let getOwnerIds = { (rule: FilterRule) -> [UInt]? in
            switch rule.value {
            case let .number(id):
                return [UInt(id)]
            case let .invalid(value):
                Logger.shared.warning("Recovering multi-value rule \(String(describing: rule.ruleType), privacy: .public) from value \(String(describing: value), privacy: .public)")
                return value.components(separatedBy: ",").compactMap { UInt($0) }
            default:
                return nil
            }
        }

        for rule in rules {
            switch rule.ruleType {
            case .title, .content, .titleContent, .fulltextQuery:
                guard let mode = SearchMode(ruleType: rule.ruleType) else {
                    fatalError("Could not convert rule type to search mode (this should not occur)")
                }
                searchMode = mode
                guard case let .string(v) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }
                searchText = v

            case .correspondent:
                guard case let .correspondent(id) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                correspondent = id == nil ? .notAssigned : .anyOf(ids: [id!])

            case .hasCorrespondentAny:
                correspondent = handleElementAny(ids: rule.value.correspondentId,
                                                 filter: correspondent,
                                                 rule: rule)

            case .doesNotHaveCorrespondent:
                correspondent = handleElementNone(ids: rule.value.correspondentId,
                                                  filter: correspondent,
                                                  rule: rule)

            case .documentType:
                guard case let .documentType(id) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                documentType = id == nil ? .notAssigned : .anyOf(ids: [id!])

            case .hasDocumentTypeAny:
                documentType = handleElementAny(ids: rule.value.documentTypeId,
                                                filter: documentType,
                                                rule: rule)

            case .doesNotHaveDocumentType:
                documentType = handleElementNone(ids: rule.value.documentTypeId,
                                                 filter: documentType,
                                                 rule: rule)

            case .storagePath:
                guard case let .storagePath(id) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }
                storagePath = id == nil ? .notAssigned : .anyOf(ids: [id!])

            case .hasStoragePathAny:
                storagePath = handleElementAny(ids: rule.value.storagePathId,
                                               filter: storagePath,
                                               rule: rule)

            case .doesNotHaveStoragePath:
                storagePath = handleElementNone(ids: rule.value.storagePathId,
                                                filter: storagePath,
                                                rule: rule)

            case .hasTagsAll:
                guard let ids = getTagIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                if case let .allOf(include, exclude) = tags {
                    // have allOf already
                    self.tags = .allOf(include: include + ids, exclude: exclude)
                } else if case .any = tags {
                    self.tags = .allOf(include: ids, exclude: [])
                } else {
                    Logger.shared.error("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                }

            case .doesNotHaveTag:
                guard let ids = getTagIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                if case let .allOf(include, exclude) = tags {
                    // have allOf already
                    self.tags = .allOf(include: include, exclude: exclude + ids)
                } else if case .any = tags {
                    self.tags = .allOf(include: [], exclude: ids)
                } else {
                    Logger.shared.error("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                    break
                }

            case .hasTagsAny:
                guard let ruleIds = getTagIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                if case let .anyOf(ids) = tags {
                    tags = .anyOf(ids: ids + ruleIds)
                } else if case .any = tags {
                    tags = .anyOf(ids: ruleIds)
                } else {
                    Logger.shared.error("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                    break
                }

            case .hasAnyTag:
                guard case let .boolean(value) = rule.value, value == false else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                switch tags {
                case .anyOf:
                    fallthrough
                case .allOf:
                    print("Have filter state .allOf or .anyOf, but found is-not-tagged rule")
                    remaining.append(rule)
                case .any:
                    tags = .notAssigned
                case .notAssigned:
                    // nothing to do, redundant rule probably
                    break
                }

            case .owner:
                guard case let .number(id) = rule.value, id >= 0 else {
                    Logger.shared.error("Invalid value for rule type \(String(describing: rule.ruleType))")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case let .anyOf(ids):
                    if !(ids.count == 1 && ids[0] == id) {
                        Logger.shared.error("Owner is already set to .anyOf, but got other owner")
                    }
                    fallthrough // reset anyway
                case .noneOf:
                    Logger.shared.error("Owner is already set to .noneOf, but got explicit owner")
                    fallthrough // reset anyway
                case .notAssigned:
                    Logger.shared.error("Already have ownerIsnull rule, but got explicit owner")
                    fallthrough // reset anyway
                case .any:
                    owner = .anyOf(ids: [UInt(id)])
                }

            case .ownerIsnull:
                guard case let .boolean(value) = rule.value else {
                    Logger.shared.error("Invalid value for rule type \(String(describing: rule.ruleType))")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case .anyOf:
                    Logger.shared.error("Owner is already set to .anyOf, but got ownerIsnull=\(value)")
                    fallthrough // reset anyway
                case .noneOf:
                    Logger.shared.error("Owner is already set to .noneOf, but got ownerIsnull=\(value)")
                    fallthrough // reset anyway
                case .notAssigned:
                    Logger.shared.error("Already have ownerIsnull rule, but got ownerIsnull=\(value)")
                    fallthrough // reset anyway
                case .any:
                    owner = value ? .notAssigned : .any
                }

            case .ownerAny:
                guard let ids = getOwnerIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case let .anyOf(existing):
                    owner = .anyOf(ids: existing + ids)
                case .noneOf, .notAssigned:
                    let ownerCopy = owner
                    Logger.shared.error("Owner is already set to \(String(describing: ownerCopy)), but got rule ownerAny=\(ids)")
                    fallthrough // reset anyway
                case .any:
                    owner = .anyOf(ids: ids)
                }

            case .ownerDoesNotInclude:
                guard let ids = getOwnerIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case let .noneOf(existing):
                    owner = .noneOf(ids: existing + ids)
                case .anyOf, .notAssigned:
                    let ownerCopy = owner
                    Logger.shared.error("Owner is already set to \(String(describing: ownerCopy)), but got rule ownerDoesNotInclude=\(ids)")
                    fallthrough // reset anyway
                case .any:
                    owner = .noneOf(ids: ids)
                }

            default:
                remaining.append(rule)
            }
        }
    }

    // MARK: Methods

    mutating func handleElementAny(ids: [UInt]?, filter: Filter,
                                   rule: FilterRule) -> Filter
    {
        guard let ids else {
            Logger.shared.error("Invalid value for rule type or nil id \(String(describing: rule.ruleType)), \(String(describing: rule.value))")
            remaining.append(rule)
            return filter
        }

        switch filter {
        case let .anyOf(existing):
            return .anyOf(ids: existing + ids)
        case .noneOf:
            Logger.shared.notice("Rule set combination invalid: anyOf + noneOf")
            fallthrough
        default:
            return .anyOf(ids: ids)
        }
    }

    mutating func handleElementNone(ids: [UInt]?, filter: Filter, rule: FilterRule) -> Filter {
        guard let ids else {
            Logger.shared.error("Invalid value for rule type or nil id \(String(describing: rule.ruleType)), \(String(describing: rule.value))")
            remaining.append(rule)
            return filter
        }

        switch filter {
        case let .noneOf(existing):
            return .noneOf(ids: existing + ids)
        case .anyOf:
            Logger.shared.notice("Rule set combination invalid: anyOf + noneOf")
            fallthrough
        default:
            return .noneOf(ids: ids)
        }
    }

    var rules: [FilterRule] {
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

    var filtering: Bool {
        ruleCount > 0 || !defaultSorting
    }

    var ruleCount: Int {
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

    mutating func clear() {
//        documentType = .any
//        correspondent = .any
//        tags = .any
//        searchText = ""
//        searchMode = .titleContent
//        savedView = nil
//        modified = false
        self = FilterState()
    }
}
