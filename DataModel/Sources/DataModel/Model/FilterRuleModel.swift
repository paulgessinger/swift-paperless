//
//  FilterRuleModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.04.23.
//

import Common
import Foundation
import os

extension FilterRuleType: Codable {}

public enum FilterRuleValue: Equatable, Sendable {
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
            dateFormatter.timeZone = .gmt
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

    public var correspondentId: [UInt]? {
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

    public var documentTypeId: [UInt]? {
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

    public var storagePathId: [UInt]? {
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

public struct FilterRule: Equatable, Sendable {
    public var ruleType: FilterRuleType
    public var value: FilterRuleValue

    public init?(ruleType: FilterRuleType, value: FilterRuleValue) {
        switch (ruleType.dataType(), value) {
        case (.date, .date), (.number, .number), (.tag, .tag), (.boolean, .boolean), (.documentType, .documentType), (.storagePath, .storagePath), (.correspondent, .correspondent), (.number, .owner), (.string, .string):
            self.ruleType = ruleType
            self.value = value

        // For all other cases, we can just use the value as is, IF it matches the rule type
        case (_, .date, .date), (_, .number, .number), (_, .tag, .tag), (_, .boolean, .boolean),
             (_, .documentType, .documentType), (_, .storagePath, .storagePath),
             (_, .correspondent, .correspondent), (_, .number, .owner), (_, .string, .string):
            self.value = value

        case let (_, _, .invalid(str)):
            self.value = .invalid(value: str)

        default:
            return nil
        }
    }

    public static func queryItems(for rules: [FilterRule]) -> [URLQueryItem] {
        var result: [URLQueryItem] = []

        let rulesMultiple = rules.filter { $0.ruleType.multiple() }

        let groups = Dictionary(grouping: rulesMultiple, by: { $0.ruleType })

        for (type, group) in groups {
            let values = group.compactMap { $0.value.string() }.sorted()

            if let filterVar = type.filterVar() {
                result.append(.init(name: filterVar, value: values.joined(separator: ",")))
            } else {
//                Logger.shared.warning("Unable to add query item for \(String(reflecting: type), privacy: .public)")
            }
        }

        for rule in rules.filter({ !$0.ruleType.multiple() }) {
            guard let filterVar = rule.ruleType.filterVar() else {
//                Logger.shared.warning("Unable to add query item for \(String(reflecting: rule.ruleType), privacy: .public)")
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
    private enum CodingKeys: String, CodingKey {
        case ruleType = "rule_type"
        case value
    }

    public init(from decoder: any Decoder) throws {
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
//                    Logger.shared.error("Unable to decode filter rule date string: \(dateStr, privacy: .public)")
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

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(ruleType, forKey: .ruleType)

        try container.encode(value.string(), forKey: .value)
    }
}
