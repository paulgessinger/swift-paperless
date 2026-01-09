//
//  Route.swift
//  Common
//
//  Created by Paul Gessinger on 04.01.26.
//

import DataModel
import Foundation

public struct Route: Equatable, Sendable {

  /// Captures filter parameters from deep link URLs
  /// All properties are optional - nil means don't change that filter
  public struct DeepLinkFilter: Equatable, Sendable {
    public var tags: FilterState.TagFilter? = nil
    public var correspondent: FilterState.Filter? = nil
    public var documentType: FilterState.Filter? = nil
    public var storagePath: FilterState.Filter? = nil
    public var owner: FilterState.Filter? = nil
    public var searchText: String? = nil
    public var searchMode: FilterState.SearchMode? = nil
    public var asn: FilterState.AsnFilter? = nil
    public var dateCreated: FilterState.DateFilter.Argument? = nil
    public var dateAdded: FilterState.DateFilter.Argument? = nil
    public var dateModified: FilterState.DateFilter.Argument? = nil
    public var sortField: SortField? = nil
    public var sortOrder: DataModel.SortOrder? = nil

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case document(id: UInt, edit: Bool)
    case setFilter(DeepLinkFilter)
    case clearFilter
    case scan

    public enum FilterSetting: String, Equatable, Sendable {
      case tags, correspondent, documentType, storagePath, asn, date, customField
    }
    case openFilterSettings(_: FilterSetting)
    case closeFilterSettings
  }

  public enum ParseError: Error, Equatable, Sendable {
    case invalidUrl
    case unsupportedVersion(String?)
    case missingPath
    case unknownResource(String)
    case missingDocumentId
    case invalidDocumentId(String)
    case invalidEditValue(String)
    case invalidTagMode(String)
    case excludedTagsNotAllowedInAnyMode
    case invalidSearchMode(String)
    case invalidAsnValue(String)
    case invalidDateFormat(String)
    case invalidSortField(String)
    case mixedFilterIdsNotAllowed(String)
    case unsupportedModifiedDateFilter
    case unsupportedPreviousIntervalDateFilter
  }

  public let action: Action
  public let server: String?

  public init(from url: URL) throws {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw ParseError.invalidUrl
    }

    guard let host = components.host, !host.isEmpty else {
      throw ParseError.unsupportedVersion(nil)
    }

    guard host == "v1" else {
      throw ParseError.unsupportedVersion(host)
    }

    // Parse optional server from query string
    server = components.queryItems?.first(where: { $0.name == "server" })?.value

    var parts = components.path.split(separator: "/")

    guard parts.count >= 1 else {
      throw ParseError.missingPath
    }

    let resource = parts.removeFirst()

    switch resource {
    case "document":
      guard parts.count == 1 else {
        throw ParseError.missingDocumentId
      }

      let idString = String(parts.removeFirst())
      guard let id = UInt(idString) else {
        throw ParseError.invalidDocumentId(idString)
      }

      // Parse optional edit parameter
      let edit = try Self.parseEditParameter(from: components.queryItems ?? [])

      self.action = .document(id: id, edit: edit)

    case "scan":
      guard parts.isEmpty else {
        throw ParseError.unknownResource(String(resource))
      }
      self.action = .scan

    case "set_filter":
      guard parts.isEmpty else {
        throw ParseError.unknownResource(String(resource))
      }
      var filter = DeepLinkFilter()
      filter.tags = try Self.parseTagFilter(from: components.queryItems ?? [])
      filter.correspondent = try Self.parseSimpleFilter(
        from: components.queryItems ?? [], paramName: "correspondent")
      filter.documentType = try Self.parseSimpleFilter(
        from: components.queryItems ?? [], paramName: "document_type")
      filter.storagePath = try Self.parseSimpleFilter(
        from: components.queryItems ?? [], paramName: "storage_path")
      filter.owner = try Self.parseSimpleFilter(
        from: components.queryItems ?? [], paramName: "owner")

      let (searchText, searchMode) = try Self.parseSearchParameters(
        from: components.queryItems ?? [])
      filter.searchText = searchText
      filter.searchMode = searchMode

      filter.asn = try Self.parseAsnFilter(from: components.queryItems ?? [])

      filter.dateCreated = try Self.parseDateFilter(
        from: components.queryItems ?? [], paramName: "date_created")
      filter.dateAdded = try Self.parseDateFilter(
        from: components.queryItems ?? [], paramName: "date_added")
      filter.dateModified = try Self.parseDateFilter(
        from: components.queryItems ?? [], paramName: "date_modified")

      let (sortField, sortOrder) = try Self.parseSortParameters(
        from: components.queryItems ?? [])
      filter.sortField = sortField
      filter.sortOrder = sortOrder

      self.action = .setFilter(filter)

    case "clear_filter":
      guard parts.isEmpty else {
        throw ParseError.unknownResource(String(resource))
      }
      self.action = .clearFilter

    case "open_filter":
      guard parts.count == 1 else {
        throw ParseError.unknownResource(String(resource))
      }

      let settingString = String(parts.removeFirst())
      guard let filterSetting = Action.FilterSetting(rawValue: settingString) else {
        throw ParseError.unknownResource(settingString)
      }

      self.action = .openFilterSettings(filterSetting)

    case "close_filter":
      guard parts.isEmpty else {
        throw ParseError.unknownResource(String(resource))
      }
      self.action = .closeFilterSettings

    default:
      throw ParseError.unknownResource(String(resource))
    }

  }

  static private func parseTagFilter(from queryItems: [URLQueryItem]) throws -> FilterState
    .TagFilter?
  {
    guard let tagQuery = queryItems.first(where: { $0.name == "tags" })?.value else {
      return nil
    }

    // Empty tags parameter means nil (don't change filter)
    guard !tagQuery.isEmpty else {
      return nil
    }

    let tagMode = queryItems.first(where: { $0.name == "tag_mode" })?.value ?? "any"

    guard tagMode == "any" || tagMode == "all" else {
      throw ParseError.invalidTagMode(tagMode)
    }

    switch tagQuery {
    case "none":
      return .notAssigned
    case "any":
      return .any
    default:
      let tagStrings = tagQuery.split(separator: ",")
      var include = [UInt]()
      var exclude = [UInt]()
      for tagString in tagStrings {
        if tagString.hasPrefix("!"), let id = UInt(tagString.dropFirst()) {
          exclude.append(id)
          continue
        }

        if let id = UInt(tagString) {
          include.append(id)
        }
      }

      switch tagMode {
      case "any":
        guard exclude.isEmpty else {
          throw ParseError.excludedTagsNotAllowedInAnyMode
        }
        return .anyOf(ids: include)
      case "all":
        return .allOf(include: include, exclude: exclude)
      default:
        throw ParseError.invalidTagMode(tagMode)
      }
    }
  }

  /// Parses search text and search mode parameters
  /// Returns (searchText, searchMode) tuple - both nil if not provided
  static private func parseSearchParameters(from queryItems: [URLQueryItem]) throws -> (
    String?, FilterState.SearchMode?
  ) {
    let searchText = queryItems.first(where: { $0.name == "search" })?.value

    guard let searchModeValue = queryItems.first(where: { $0.name == "search_mode" })?.value else {
      return (searchText, nil)
    }

    let searchMode: FilterState.SearchMode?
    switch searchModeValue {
    case "title":
      searchMode = .title
    case "content":
      searchMode = .content
    case "title_content":
      searchMode = .titleContent
    case "advanced":
      searchMode = .advanced
    default:
      throw ParseError.invalidSearchMode(searchModeValue)
    }

    return (searchText, searchMode)
  }

  /// Parses simple ID-based filters (correspondent, documentType, storagePath, owner)
  /// Supports: `param=1,2,3` (anyOf), `param=!1,!2` (noneOf), `param=none` (notAssigned), `param=any` (.any)
  static private func parseSimpleFilter(from queryItems: [URLQueryItem], paramName: String) throws
    -> FilterState.Filter?
  {
    guard let value = queryItems.first(where: { $0.name == paramName })?.value else {
      return nil
    }

    // Empty parameter means nil (don't change filter)
    guard !value.isEmpty else {
      return nil
    }

    // Handle special values
    switch value {
    case "none":
      return .notAssigned
    case "any":
      return .any
    default:
      // Parse comma-separated IDs with optional ! prefix for exclusion
      let idStrings = value.split(separator: ",")
      var includeIds = [UInt]()
      var excludeIds = [UInt]()

      for idString in idStrings {
        if idString.hasPrefix("!"), let id = UInt(idString.dropFirst()) {
          excludeIds.append(id)
        } else if let id = UInt(idString) {
          includeIds.append(id)
        }
      }

      // If all IDs are excluded, use noneOf
      if !excludeIds.isEmpty && includeIds.isEmpty {
        return .noneOf(ids: excludeIds)
      }

      // Mixing include/exclude is not supported for simple filters
      if !excludeIds.isEmpty && !includeIds.isEmpty {
        throw ParseError.mixedFilterIdsNotAllowed(paramName)
      }

      // If we have included IDs, use anyOf (exclude not supported in anyOf)
      if !includeIds.isEmpty {
        return .anyOf(ids: includeIds)
      }

      // No valid IDs parsed, return nil
      return nil
    }
  }

  /// Parses ASN (Archive Serial Number) filter parameters
  /// Supports: `asn=123` (equalTo), `asn_gt=100` (greaterThan), `asn_lt=200` (lessThan),
  ///           `asn=null` (isNull), `asn=not_null` (isNotNull), `asn=any` (.any)
  static private func parseAsnFilter(from queryItems: [URLQueryItem]) throws -> FilterState
    .AsnFilter?
  {
    let asnValue = queryItems.first(where: { $0.name == "asn" })?.value
    let asnGt = queryItems.first(where: { $0.name == "asn_gt" })?.value
    let asnLt = queryItems.first(where: { $0.name == "asn_lt" })?.value

    // If no ASN parameters provided, return nil
    guard asnValue != nil || asnGt != nil || asnLt != nil else {
      return nil
    }

    // Handle asn parameter
    if let value = asnValue {
      guard !value.isEmpty else {
        return nil
      }

      switch value {
      case "any":
        return .any
      case "null":
        return .isNull
      case "not_null":
        return .isNotNull
      default:
        guard let asn = UInt(value) else {
          throw ParseError.invalidAsnValue(value)
        }
        return .equalTo(asn)
      }
    }

    // Handle asn_gt parameter
    if let value = asnGt {
      guard !value.isEmpty else {
        return nil
      }
      guard let asn = UInt(value) else {
        throw ParseError.invalidAsnValue(value)
      }
      return .greaterThan(asn)
    }

    // Handle asn_lt parameter
    if let value = asnLt {
      guard !value.isEmpty else {
        return nil
      }
      guard let asn = UInt(value) else {
        throw ParseError.invalidAsnValue(value)
      }
      return .lessThan(asn)
    }

    return nil
  }

  /// Parses date filters for created/added/modified
  /// Supports: `date_param=today`, `date_param=current_month`, `date_param=previous_week`,
  ///           `date_param_from=YYYY-MM-DD`, `date_param_to=YYYY-MM-DD`, `date_param=any`
  static private func parseDateFilter(
    from queryItems: [URLQueryItem],
    paramName: String
  ) throws -> FilterState.DateFilter.Argument? {
    let value = queryItems.first(where: { $0.name == paramName })?.value
    let fromValue = queryItems.first(where: { $0.name == "\(paramName)_from" })?.value
    let toValue = queryItems.first(where: { $0.name == "\(paramName)_to" })?.value

    if let value {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        return nil
      }

      if trimmed == "any" {
        return .any
      }

      let normalized = trimmed.lowercased().replacingOccurrences(of: "_", with: " ")
      if let range = parseWithinRange(from: normalized) {
        return .range(range)
      }

      throw ParseError.invalidDateFormat(trimmed)
    }

    guard fromValue != nil || toValue != nil else {
      return nil
    }

    let start = try parseDateValue(fromValue)
    let end = try parseDateValue(toValue)

    guard start != nil || end != nil else {
      return nil
    }

    return .between(start: start, end: end)
  }

  static private func parseWithinRange(
    from value: String
  ) -> FilterState.DateFilter.Range? {
    let ex = /within\s*(?<count>\d+)\s*(?<unit>[wmy])/
    guard let match = try? ex.wholeMatch(in: value),
      let count = Int(match.count),
      count > 0
    else {
      return nil
    }

    switch match.unit {
    case "w":
      guard count == 1 else {
        return nil
      }
      return .within(num: -1, interval: .week)
    case "m":
      guard count == 1 || count == 3 else {
        return nil
      }
      return .within(num: -count, interval: .month)
    case "y":
      guard count == 1 else {
        return nil
      }
      return .within(num: -1, interval: .year)
    default:
      return nil
    }
  }

  static private func parseDateValue(_ value: String?) throws -> Date? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    let ex = /(\d{4}-\d{2}-\d{2}).*/
    guard let match = try? ex.wholeMatch(in: trimmed) else {
      throw ParseError.invalidDateFormat(trimmed)
    }

    let formatter = DateFormatter()
    formatter.timeZone = .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: String(match.1)) else {
      throw ParseError.invalidDateFormat(trimmed)
    }

    return date
  }

  /// Parses sort field and order parameters
  /// Supports `sort_field` with API field names or aliases, and `sort_order` as `asc`/`desc`.
  static private func parseSortParameters(
    from queryItems: [URLQueryItem]
  ) throws -> (SortField?, DataModel.SortOrder?) {
    let sortFieldValue = queryItems.first(where: { $0.name == "sort_field" })?.value
    let sortOrderValue = queryItems.first(where: { $0.name == "sort_order" })?.value

    let sortField = try parseSortField(sortFieldValue)
    let sortOrder = try parseSortOrder(sortOrderValue)

    return (sortField, sortOrder)
  }

  static private func parseSortField(_ value: String?) throws -> SortField? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    let normalized = trimmed.lowercased()
    let mappedValue: String
    switch normalized {
    case "asn":
      mappedValue = SortField.asn.rawValue
    case "correspondent":
      mappedValue = SortField.correspondent.rawValue
    case "document_type":
      mappedValue = SortField.documentType.rawValue
    case "storage_path":
      mappedValue = SortField.storagePath.rawValue
    default:
      mappedValue = normalized
    }

    let field = SortField(rawValue: mappedValue)
    if case .other = field {
      throw ParseError.invalidSortField(trimmed)
    }

    return field
  }

  static private func parseSortOrder(_ value: String?) throws -> DataModel.SortOrder? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }

    switch trimmed.lowercased() {
    case "asc", "ascending":
      return .ascending
    case "desc", "descending":
      return .descending
    default:
      throw ParseError.invalidSortField(trimmed)
    }
  }

  /// Parses the edit parameter from query items
  /// Accepts "true", "1", "yes" as true; "false", "0", "no" as false
  /// Missing parameter defaults to false
  /// Any other value throws an error
  static private func parseEditParameter(from queryItems: [URLQueryItem]) throws -> Bool {
    guard let value = queryItems.first(where: { $0.name == "edit" })?.value else {
      return false
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    switch trimmed {
    case "true", "1", "yes":
      return true
    case "false", "0", "no":
      return false
    default:
      throw ParseError.invalidEditValue(value)
    }
  }

}
