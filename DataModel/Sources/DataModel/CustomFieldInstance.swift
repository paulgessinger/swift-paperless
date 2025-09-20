import Foundation
import os

public enum CustomFieldValue: Sendable, Equatable, Hashable {
  public enum InvalidReason: Sendable, Hashable, Equatable {
    case invalidDate(String)
    case invalidURL(String)
    case invalidMonetary(String)
    case invalidSelectOption(String)
    case unknownValue
    case unknownDataType(String)
    case typeMismatch(dataType: CustomField.DataType, value: CustomFieldRawValue)
  }

  case string(String)
  case boolean(Bool)
  case date(Date?)
  case select(CustomField.SelectOption?)
  case documentLink([UInt])
  case url(URL?)
  case integer(Int?)
  case float(Double?)
  case monetary(currency: String, amount: Decimal?)
  case invalid(InvalidReason)

  public static func formatMonetary(currency: String, amount: Decimal?) -> String {
    let formattedAmount = (amount ?? 0).formatted(
      .number
        .locale(Locale(identifier: "en_US"))
        .grouping(.never)
        .decimalSeparator(strategy: .always)
        .precision(.fractionLength(2)))

    return "\(currency)\(formattedAmount)"
  }

  public var rawValue: CustomFieldRawValue {
    switch self {
    case .string(let value):
      .string(value)

    case .boolean(let value):
      .boolean(value)

    case .date(let value):
      value.map { .string(CustomFieldInstance.dateFormatter.string(from: $0)) } ?? .none

    case .select(let value):
      value.map { .string($0.id) } ?? .none

    case .documentLink(let value):
      .idList(value)

    case .url(let value):
      value.map {
        .string($0.absoluteString)
      } ?? .none

    case .monetary(let currency, let amount):
      amount.map { .string(CustomFieldValue.formatMonetary(currency: currency, amount: $0)) }
        ?? .none

    case .integer(let value):
      value.map { .integer($0) } ?? .none

    case .float(let value):
      value.map { .float($0) } ?? .none

    case .invalid:
      .unknown
    }
  }

  public var isValid: Bool {
    switch self {
    case .monetary(let currency, _):
      let ex = /^[A-Z]{3}$/
      return currency.wholeMatch(of: ex) != nil

    case .url(let url):
      guard let url else {
        return true
      }
      return url.scheme != nil && url.host != nil

    default: return true
    }
  }
}

public struct CustomFieldInstance: Sendable, Hashable {
  public let field: CustomField
  public var value: CustomFieldValue

  public init(field: CustomField, value: CustomFieldValue) {
    self.field = field
    self.value = value
  }

  public static func withDefaultValue(field: CustomField, locale: Locale) -> CustomFieldInstance {
    let value: CustomFieldValue
    switch field.dataType {
    case .string:
      value = .string("")
    case .boolean:
      value = .boolean(false)
    case .date:
      value = .date(nil)
    case .select:
      value = .select(nil)
    case .documentLink:
      value = .documentLink([])
    case .url:
      value = .url(nil)
    case .integer:
      value = .integer(nil)
    case .float:
      value = .float(nil)
    case .monetary:
      let currency = field.extraData.defaultCurrency ?? locale.currency?.identifier ?? ""
      value = .monetary(currency: currency, amount: nil)
    case .other:
      value = .invalid(.unknownDataType(field.dataType.rawValue))
    }

    return CustomFieldInstance(field: field, value: value)
  }

  public var isValid: Bool {
    switch (field.dataType, value) {
    case (.string, .string): return true

    case (.boolean, .boolean): return true

    case (.date, .date): return true

    case (.select, .select(let option)):
      // nil option is valid
      guard let option else { return true }
      return field.extraData.selectOptions.contains { $0.id == option.id }

    case (.documentLink, .documentLink): return true

    case (.url, .url(let url)):
      guard let url else {
        return true
      }
      return url.scheme != nil && url.host != nil

    case (.integer, .integer): return true

    case (.float, .float): return true

    case (.monetary, .monetary(let currency, _)):
      let ex = /^[A-Z]{3}$/
      return currency.wholeMatch(of: ex) != nil

    default: return false
    }
  }

  public static let dateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df
  }()
}

extension CustomFieldInstance {
  public init(field: CustomField, rawValue: CustomFieldRawValue, locale: Locale) {
    self.field = field
    switch (field.dataType, rawValue) {
    case (.string, .string(let value)):
      self.value = .string(value)

    case (.string, .none):
      value = .string("")

    case (.float, .float(let value)):
      self.value = .float(value)

    case (.float, .integer(let value)):
      self.value = .float(Double(value))

    case (.float, .none):
      value = .float(nil)

    case (.boolean, .boolean(let value)):
      self.value = .boolean(value)

    case (.boolean, .none):
      value = .boolean(false)

    case (.date, .string(let value)):
      if let date = CustomFieldInstance.dateFormatter.date(from: value) {
        self.value = .date(date)
      } else {
        Logger.dataModel.error(
          "Invalid date format: \(value) for field \(field.name, privacy: .public)")
        self.value = .invalid(.invalidDate(value))
      }

    case (.date, .none):
      value = .date(nil)

    case (.documentLink, .idList(let value)):
      self.value = .documentLink(value)

    case (.documentLink, .none):
      value = .documentLink([])

    case (.url, .string(let value)):
      if value.isEmpty {
        self.value = .url(nil)
      } else if let url = URL(string: value) {
        self.value = .url(url)
      } else {
        Logger.dataModel.error(
          "Invalid URL format: \(value) for field \(field.name, privacy: .private)")
        self.value = .invalid(.invalidURL(value))
      }

    case (.url, .none):
      value = .url(nil)

    case (.monetary, .none):
      let currency = field.extraData.defaultCurrency ?? locale.currency?.identifier ?? ""
      value = .monetary(currency: currency, amount: nil)

    case (.monetary, .string(let value)):
      let regex = /^(?<currency>[A-Z]{3})?(?<amount>\d+(?:\.\d{2})?)$/

      guard let match = value.wholeMatch(of: regex) else {
        Logger.dataModel.error(
          "Invalid monetary format: \(value) for field \(field.name, privacy: .private)")
        self.value = .invalid(.invalidMonetary(value))
        return
      }

      let currency: String =
        if let cur = match.currency {
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
        self.value = .invalid(.invalidMonetary(value))
        return
      }

      self.value = .monetary(currency: currency, amount: amount)

    case (.select, .string(let value)):
      let option = field.extraData.selectOptions.first { $0.id == value }

      if let option {
        self.value = .select(option)
      } else {
        Logger.dataModel.error(
          "Invalid select option: \(value, privacy: .public) for field \(field.name, privacy: .public)"
        )
        self.value = .invalid(.invalidSelectOption(value))
      }

    case (.select, .none):
      value = .select(nil)

    case (.integer, .integer(let value)):
      self.value = .integer(value)

    case (.integer, .none):
      value = .integer(nil)

    case (_, .unknown):
      Logger.dataModel.error(
        "Unknown custom field value: \(String(describing: rawValue), privacy: .public) for field \(field.id, privacy: .public)"
      )
      value = .invalid(.unknownValue)

    case (.other(let dataType), _):
      Logger.dataModel.error(
        "Unknown custom field data type: \(field.dataType.rawValue, privacy: .public) for field \(field.id, privacy: .public) with value \(String(describing: rawValue), privacy: .public)"
      )
      value = .invalid(.unknownDataType(dataType))

    default:
      Logger.dataModel.error(
        "Type mismatch for field \(field.id, privacy: .public) with value \(String(describing: rawValue), privacy: .public)"
      )
      value = .invalid(.typeMismatch(dataType: field.dataType, value: rawValue))
    }
  }

  public var rawEntry: CustomFieldRawEntry {
    CustomFieldRawEntry(field: field.id, value: value.rawValue)
  }
}

extension [CustomFieldInstance] {
  public static func fromRawEntries(
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

  public var rawEntries: CustomFieldRawEntryList {
    .init(map(\.rawEntry))
  }

  public var hasInvalidValues: Bool {
    contains { !$0.isValid }
  }
}
