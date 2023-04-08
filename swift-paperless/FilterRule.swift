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

struct FilterRule: Codable, Equatable {
    var ruleType: FilterRuleType
    var value: FilterRuleValue

    init(ruleType: FilterRuleType, value: FilterRuleValue) {
        self.ruleType = ruleType
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case ruleType = "rule_type"
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ruleType = try container.decode(FilterRuleType.self, forKey: .ruleType)
        switch ruleType.dataType() {
        case .date:
            let dateStr = try container.decode(String.self, forKey: .value)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            guard let date = dateFormatter.date(from: dateStr) else {
                throw DateDecodingError.invalidDate(string: dateStr)
            }
            self.value = .date(value: date)

//            self.value = try .date(value: container.decode(Date.self, forKey: .value))
        case .number:
            self.value = try .number(value: container.decodeOrConvert(Int.self, forKey: .value))
        case .tag:
            self.value = try .tag(id: container.decodeOrConvert(UInt.self, forKey: .value))
        case .boolean:
            self.value = try .boolean(value: container.decodeOrConvert(Bool.self, forKey: .value))
        case .documentType:
            self.value = try .documentType(id: container.decodeOrConvertOptional(UInt.self, forKey: .value))
        case .storagePath:
            self.value = try .storagePath(id: container.decodeOrConvertOptional(UInt.self, forKey: .value))
        case .correspondent:
            self.value = try .correspondent(id: container.decodeOrConvertOptional(UInt.self, forKey: .value))
        case .string:
            self.value = try .string(value: container.decodeOrConvert(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(ruleType, forKey: .ruleType)

        try container.encode(value.string(), forKey: .value)
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
            if let value = rule.value.string() {
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
