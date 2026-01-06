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
    case document(id: UInt)
    case setFilter(DeepLinkFilter)
    case clearFilter
    case scan
  }

  public enum ParseError: Error, Equatable, Sendable {
    case invalidUrl
    case unsupportedVersion(String?)
    case missingPath
    case unknownResource(String)
    case missingDocumentId
    case invalidDocumentId(String)
    case invalidTagMode(String)
    case excludedTagsNotAllowedInAnyMode
    case invalidSearchMode(String)
    case invalidAsnValue(String)
    case invalidDateFormat(String)
    case invalidSortField(String)
  }

  public let action: Action
  public let server: String?

  public init(from url: URL) throws {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw ParseError.invalidUrl
    }

    guard let host = components.host else {
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

      self.action = .document(id: id)

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

      // TODO: Parse date and sort parameters
      self.action = .setFilter(filter)

    case "clear_filter":
      guard parts.isEmpty else {
        throw ParseError.unknownResource(String(resource))
      }
      self.action = .clearFilter

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

}
