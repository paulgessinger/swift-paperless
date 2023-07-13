//
//  FilterRule.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.04.23.
//

import Foundation

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

    fileprivate func string() -> String? {
        var s: String? = nil
        switch self {
        case .date(let value):
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            s = dateFormatter.string(from: value)
        case .number(let value):
            s = String(value)
        case .tag(let id):
            s = String(id)
        case .boolean(let value):
            s = String(value)
        case .documentType(let id):
            s = id == nil ? nil : String(id!)
        case .storagePath(let id):
            s = id == nil ? nil : String(id!)
        case .correspondent(let id):
            s = id == nil ? nil : String(id!)
        case .owner(let id):
            s = id == nil ? nil : String(id!)
        case .string(let value):
            s = value
        }
        return s
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

            result.append(.init(name: type.filterVar(), value: values.joined(separator: ",")))
        }

        for rule in rules.filter({ !$0.ruleType.multiple() }) {
            if case .boolean(let value) = rule.value {
                result.append(.init(name: rule.ruleType.filterVar(), value: value ? "1" : "0"))
            }
            else if let value = rule.value.string() {
                result.append(.init(name: rule.ruleType.filterVar(), value: value))
            }
            else {
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
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ruleType = try container.decode(FilterRuleType.self, forKey: .ruleType)

        switch ruleType.dataType() {
        case .date:
            let dateStr = try container.decode(String.self, forKey: .value)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
            guard let date = dateFormatter.date(from: dateStr) else {
                throw DateDecodingError.invalidDate(string: dateStr)
            }
            value = .date(value: date)

//            self.value = try .date(value: container.decode(Date.self, forKey: .value))
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(ruleType, forKey: .ruleType)

        try container.encode(value.string(), forKey: .value)
    }
}

enum SortField: String, Codable, CaseIterable {
    case asn = "archive_serial_number"
    case correspondent = "correspondent__name"
    case title
    case documentType = "document_type__name"
    case created
    case added
    case modified

    var label: String {
        switch self {
        case .asn:
            return "ASN"
        case .correspondent:
            return "Correspondent"
        case .title:
            return "Title"
        case .documentType:
            return "Document Type"
        case .created:
            return "Created"
        case .added:
            return "Added"
        case .modified:
            return "Modified"
        }
    }
}

enum SortOrder: Codable {
    case ascending
    case descending

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let reverse = try container.decode(Bool.self)
        self = reverse ? .ascending : .descending
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(reverse)
    }

    var reverse: Bool {
        switch self {
        case .ascending:
            return true
        case .descending:
            return false
        }
    }

    init(_ reverse: Bool) {
        if reverse {
            self = .ascending
        }
        else {
            self = .descending
        }
    }
}

// MARK: - FilterState

struct FilterState: Equatable, Codable {
    enum Filter: Equatable, Hashable, Codable {
        case any
        case notAssigned
        case only(id: UInt)
    }

    enum TagFilter: Equatable, Hashable, Codable {
        case any
        case notAssigned
        case allOf(include: [UInt], exclude: [UInt])
        case anyOf(ids: [UInt])
    }

    enum SearchMode: Equatable, Codable {
        case title
        case content
        case titleContent

        var ruleType: FilterRuleType {
            switch self {
            case .title:
                return .title
            case .content:
                return .content
            case .titleContent:
                return .titleContent
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
            default:
                return nil
            }
        }
    }

    var correspondent: Filter = .any { didSet { modified = modified || correspondent != oldValue }}
    var documentType: Filter = .any { didSet { modified = modified || documentType != oldValue }}
    var storagePath: Filter = .any { didSet { modified = modified || storagePath != oldValue }}
    var tags: TagFilter = .any { didSet { modified = modified || tags != oldValue }}
    var remaining: [FilterRule] = [] { didSet { modified = modified || remaining != oldValue }}
    var sortField: SortField = .added { didSet { modified = modified || sortField != oldValue }}
    var sortOrder: SortOrder = .ascending { didSet { modified = modified || sortOrder != oldValue }}
    var savedView: UInt? = nil
    var modified = false

    var searchText: String = "" {
        didSet {
            modified = modified || searchText != oldValue
        }
    }

    var searchMode = SearchMode.titleContent {
        didSet { modified = searchMode != oldValue }
    }

    // MARK: Initializers

    init(correspondent: FilterState.Filter = .any,
         documentType: FilterState.Filter = .any,
         storagePath: FilterState.Filter = .any,
         tags: FilterState.TagFilter = .any,
         remaining: [FilterRule] = [],
         savedView: UInt? = nil,
         searchText: String? = nil,
         searchMode: SearchMode = .titleContent)
    {
        self.correspondent = correspondent
        self.documentType = documentType
        self.storagePath = storagePath
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
        for rule in rules {
            switch rule.ruleType {
            case .title:
                fallthrough
            case .content:
                fallthrough
            case .titleContent:
                guard let mode = SearchMode(ruleType: rule.ruleType) else {
                    fatalError("Could not convert rule type to search mode (this should not occur)")
                }
                searchMode = mode
                guard case .string(let v) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }
                searchText = v

            case .correspondent:
                guard case .correspondent(let id) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                correspondent = id == nil ? .notAssigned : .only(id: id!)

            case .documentType:
                guard case .documentType(let id) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                documentType = id == nil ? .notAssigned : .only(id: id!)

            case .storagePath:
                guard case .storagePath(let id) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }
                documentType = id == nil ? .notAssigned : .only(id: id!)

            case .hasTagsAll:
                guard case .tag(let id) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                if case .allOf(let include, let exclude) = tags {
                    // have allOf already
                    self.tags = .allOf(include: include + [id], exclude: exclude)
                }
                else if case .any = tags {
                    self.tags = .allOf(include: [id], exclude: [])
                }
                else {
                    print("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                }

            case .doesNotHaveTag:
                guard case .tag(let id) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                if case .allOf(let include, let exclude) = tags {
                    // have allOf already
                    self.tags = .allOf(include: include, exclude: exclude + [id])
                }
                else if case .any = tags {
                    self.tags = .allOf(include: [], exclude: [id])
                }
                else {
                    print("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                    break
                }

            case .hasTagsAny:
                guard case .tag(let id) = rule.value else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                if case .anyOf(let ids) = tags {
                    tags = .anyOf(ids: ids + [id])
                }
                else if case .any = tags {
                    tags = .anyOf(ids: [id])
                }
                else {
                    print("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                    break
                }

            case .hasAnyTag:
                guard case .boolean(let value) = rule.value, value == false else {
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
                case .notAssigned: break
                }

            default:
                remaining.append(rule)
            }
        }
    }

    // MARK: Methods

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
        case .only(let id):
            result.append(
                .init(ruleType: .correspondent, value: .correspondent(id: id))
            )
        case .any: break
        }

        switch documentType {
        case .notAssigned:
            result.append(
                .init(ruleType: .documentType, value: .documentType(id: nil))
            )
        case .only(let id):
            result.append(
                .init(ruleType: .documentType, value: .documentType(id: id))
            )
        case .any: break
        }

        switch storagePath {
        case .notAssigned:
            result.append(
                .init(ruleType: .storagePath, value: .storagePath(id: nil)))
        case .only(let id):
            result.append(
                .init(ruleType: .storagePath, value: .storagePath(id: id)))
        case .any: break
        }

        switch tags {
        case .any: break
        case .notAssigned:
            result.append(
                .init(ruleType: .hasAnyTag, value: .boolean(value: false))
            )
        case .allOf(let include, let exclude):
            for id in include {
                result.append(
                    .init(ruleType: .hasTagsAll, value: .tag(id: id)))
            }
            for id in exclude {
                result.append(
                    .init(ruleType: .doesNotHaveTag, value: .tag(id: id)))
            }

        case .anyOf(let ids):
            for id in ids {
                result.append(
                    .init(ruleType: .hasTagsAny, value: .tag(id: id)))
            }
        }

        return result
    }

    var filtering: Bool {
//        return documentType != .any || correspondent != .any || tags != .any || !searchText.isEmpty
        return self != FilterState()
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
