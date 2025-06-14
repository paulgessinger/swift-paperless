import Foundation
import os

public enum CustomFieldValue: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case boolean(Bool)
    case date(Date)
    case select(CustomField.SelectOption)
    case documentLink([UInt])
    case url(URL)
    case integer(Int)
    case float(Double)
    case monetary(currency: String, amount: Decimal)

    public static func formatMonetary(currency: String, amount: Decimal) -> String {
        let formattedAmount = amount.formatted(
            .number
                .locale(Locale(identifier: "en_US"))
                .grouping(.never)
                .decimalSeparator(strategy: .always)
                .precision(.fractionLength(2)))

        return "\(currency)\(formattedAmount)"
    }

    var rawValue: CustomFieldRawValue {
        switch self {
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
            .string(CustomFieldValue.formatMonetary(currency: currency, amount: amount))

        case let .integer(value):
            .integer(value)

        case let .float(value):
            .float(value)
        }
    }

    var isValid: Bool {
        switch self {
        case let .monetary(currency, _):
            let ex = /^[A-Z]{3}$/
            return currency.wholeMatch(of: ex) != nil
        default: return true
        }
    }
}

public struct CustomFieldInstance: Codable, Sendable, Hashable {
    public let field: CustomField
    public var value: CustomFieldValue

    public init?(field: CustomField, value: CustomFieldValue) {
        self.field = field
        self.value = value

        guard isValid else {
            return nil
        }
    }

    var isValid: Bool {
        switch (field.dataType, value) {
        case (.string, .string): return true
        case (.boolean, .boolean): return true
        case (.date, .date): return true
        case let (.select, .select(option)):
            return field.extraData.selectOptions.contains { $0.id == option.id }
        case (.documentLink, .documentLink): return true
        case (.url, .url): return true
        case (.integer, .integer): return true
        case (.float, .float): return true
        case let (.monetary, .monetary(currency, _)):
            let ex = /^[A-Z]{3}$/
            return currency.wholeMatch(of: ex) != nil
        default: return false
        }
    }

    static let dateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

public extension CustomFieldInstance {
    init?(field: CustomField, rawValue: CustomFieldRawValue, locale: Locale) {
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
            let regex = /^(?<currency>[A-Z]{3})?(?<amount>\d+(?:\.\d{2})?)$/

            guard let match = value.wholeMatch(of: regex) else {
                Logger.dataModel.error(
                    "Invalid monetary format: \(value) for field \(field.name, privacy: .private)")
                return nil
            }

            let currency: String = if let cur = match.currency {
                String(cur)
            } else if let defaultCurrency = field.extraData.defaultCurrency {
                defaultCurrency
            } else if let localeCurrency = locale.currency {
                localeCurrency.identifier
            } else {
                ""
            }

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
        CustomFieldRawEntry(field: field.id, value: value.rawValue)
    }
}

public extension [CustomFieldInstance] {
    static func fromRawEntries(
        _ rawEntries: [CustomFieldRawEntry], customFields: [UInt: CustomField], locale: Locale
    ) -> [CustomFieldInstance] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // @TODO: Preserve somehow that this can be incomplete

        let result: [CustomFieldInstance] = rawEntries.compactMap {
            (entry: CustomFieldRawEntry) -> CustomFieldInstance? in
            guard let customField = customFields[entry.field] else {
                Logger.dataModel.error("Unknown custom field: \(entry.field, privacy: .public)")
                return nil
            }

            return CustomFieldInstance(field: customField, rawValue: entry.value, locale: locale)
        }

        return result
    }

    var rawEntries: CustomFieldRawEntryList {
        .init(map(\.rawEntry))
    }
}
