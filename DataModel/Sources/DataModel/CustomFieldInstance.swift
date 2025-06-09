import Foundation
import os

public enum CustomFieldValue: Codable, Sendable, Equatable {
    case string(String)
    case boolean(Bool)
    case date(Date)
    case select(CustomField.SelectOption)
    case documentLink([UInt])
    case url(URL)
    case integer(Int)
    case float(Double)
    case monetary(currency: String, amount: Decimal)
}

public struct CustomFieldInstance: Codable, Sendable {
    public let field: CustomField
    public let value: CustomFieldValue

    public init(field: CustomField, value: CustomFieldValue) {
        self.field = field
        self.value = value
    }

    static let dateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

public extension CustomFieldInstance {
    init?(field: CustomField, rawValue: CustomFieldRawValue) {
        self.field = field
        switch (field.dataType, rawValue) {
        case let (.string, .string(value)):
            self.value = .string(value)

        case let (.float, .float(value)):
            self.value = .float(value)

        case let (.boolean, .boolean(value)):
            self.value = .boolean(value)

        case let (.date, .string(value)):
            if let date = CustomFieldInstance.dateFormatter.date(from: value) {
                self.value = .date(date)
            } else {
                Logger.dataModel.error(
                    "Invalid date format: \(value) for field \(field.name, privacy: .public)")
                return nil
            }

        case let (.documentLink, .idList(value)):
            self.value = .documentLink(value)

        case let (.url, .string(value)):
            if let url = URL(string: value) {
                self.value = .url(url)
            } else {
                Logger.dataModel.error(
                    "Invalid URL format: \(value) for field \(field.name, privacy: .private)")
                return nil
            }

        case let (.monetary, .string(value)):
            let regex = /^(?<currency>[A-Z]{3})(?<amount>\d+(?:\.\d{2})?)$/

            guard let match = value.wholeMatch(of: regex) else {
                Logger.dataModel.error(
                    "Invalid monetary format: \(value) for field \(field.name, privacy: .private)")
                return nil
            }

            let currency = String(match.currency)
            guard let amount = Decimal(string: String(match.amount)) else {
                Logger.dataModel.error(
                    "Invalid monetary amount: \(value, privacy: .public) for field \(field.name, privacy: .public)"
                )
                return nil
            }

            self.value = .monetary(currency: currency, amount: amount)

        case let (.select, .string(value)):
            let option = field.extraData.selectOptions.first { $0.id == value }

            guard let option else {
                Logger.dataModel.error(
                    "Invalid select option: \(value) for field \(field.name, privacy: .private)")
                return nil
            }
            self.value = .select(option)

        case let (.integer, .integer(value)):
            self.value = .integer(value)

        default:
            Logger.dataModel.error(
                "Unknown custom field data type: \(field.dataType.rawValue, privacy: .public) for field \(field.id, privacy: .public) with value \(String(describing: rawValue))"
            )
            return nil
        }
    }

    var rawEntry: CustomFieldRawEntry {
        func fmt(_ value: Decimal) -> String {
            value.formatted(
                .number
                    .locale(Locale(identifier: "en_US"))
                    .grouping(.never)
                    .decimalSeparator(strategy: .always)
                    .precision(.fractionLength(2)))
        }

        let rawValue: CustomFieldRawValue =
            switch value {
            case let .string(value):
                .string(value)

            case let .boolean(value):
                .boolean(value)

            case let .date(value):
                .string(CustomFieldInstance.dateFormatter.string(from: value))

            case let .select(value):
                .string(value.id)

            case let .documentLink(value):
                .idList(value)

            case let .url(value):
                .string(value.absoluteString)

            case let .monetary(currency, amount):
                .string("\(currency)\(fmt(amount))")

            case let .integer(value):
                .integer(value)

            case let .float(value):
                .float(value)
            }

        return CustomFieldRawEntry(field: field.id, value: rawValue)
    }
}

extension [CustomFieldInstance] {
    static func fromRawEntries(
        _ rawEntries: [CustomFieldRawEntry], customFields: [UInt: CustomField]
    ) -> [CustomFieldInstance] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let result: [CustomFieldInstance] = rawEntries.compactMap {
            (entry: CustomFieldRawEntry) -> CustomFieldInstance? in
            guard let customField = customFields[entry.field] else {
                Logger.dataModel.error("Unknown custom field: \(entry.field, privacy: .public)")
                return nil
            }

            return CustomFieldInstance(field: customField, rawValue: entry.value)
        }

        return result
    }
}
