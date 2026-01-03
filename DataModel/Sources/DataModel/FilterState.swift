//
//  FilterState.swift
//  DataModel
//
//  Created by Paul Gessinger on 09.03.25.
//

import CasePaths
import Common
import Foundation
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

  public enum AsnFilter: Equatable, Codable, Sendable {
    case any
    case isNull
    case isNotNull
    case equalTo(UInt)
    case lessThan(UInt)
    case greaterThan(UInt)
  }

  public struct DateFilter: Equatable, Codable, Sendable {
    public enum Component: String, Codable, Sendable {
      case week
      case month
      case year
    }

    public enum Range: Equatable, Codable, Sendable, Hashable {
      case within(num: Int, interval: Component)
      case currentYear
      case currentMonth
      case today
      case yesterday
      case previousWeek
      case previousMonth
      case previousQuarter
      case previousYear
    }

    @CasePathable
    public enum Argument: Equatable, Codable, Sendable, Hashable {
      case any
      case between(start: Date?, end: Date?)
      case range(Range)
    }

    public var created: Argument = .any
    public var added: Argument = .any
    public var modified: Argument = .any

    public init(created: Argument = .any, added: Argument = .any, modified: Argument = .any) {
      self.created = created
      self.added = added
      self.modified = modified
    }

    public var isActive: Bool {
      created != .any || added != .any || modified != .any
    }
  }

  public var correspondent: Filter = .any {
    didSet { modified = modified || correspondent != oldValue }
  }
  public var documentType: Filter = .any {
    didSet { modified = modified || documentType != oldValue }
  }
  public var storagePath: Filter = .any {
    didSet { modified = modified || storagePath != oldValue }
  }
  public var owner: Filter = .any { didSet { modified = modified || owner != oldValue } }

  public var tags: TagFilter = .any { didSet { modified = modified || tags != oldValue } }
  public var remaining: [FilterRule] = [] {
    didSet { modified = modified || remaining != oldValue }
  }

  public var sortField: SortField {
    didSet { modified = modified || sortField != oldValue }
  }

  public var sortOrder: DataModel.SortOrder {
    didSet { modified = modified || sortOrder != oldValue }
  }

  public var customField: CustomFieldQuery = .any {
    didSet { modified = modified || customField != oldValue }
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
    didSet { modified = modified || searchMode != oldValue }
  }

  public var asn: AsnFilter {
    didSet { modified = modified || asn != oldValue }
  }

  public var date: DateFilter = .init() {
    didSet { modified = modified || date != oldValue }
  }

  public init(
    correspondent: Filter,
    documentType: Filter,
    storagePath: Filter,
    owner: Filter,
    tags: TagFilter,
    sortField: SortField,
    sortOrder: DataModel.SortOrder,
    remaining: [FilterRule],
    savedView: UInt?,
    searchText: String?,
    searchMode: SearchMode,
    customField: CustomFieldQuery,
    asn: AsnFilter
  ) {
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
    self.customField = customField
    self.asn = asn
  }

  public static var empty: FilterState {
    FilterState(
      correspondent: .any,
      documentType: .any,
      storagePath: .any,
      owner: .any,
      tags: .any,
      sortField: .asn,
      sortOrder: .descending,
      remaining: [],
      savedView: nil,
      searchText: nil,
      searchMode: .title,
      customField: .any,
      asn: .any)
  }

  public func with(_ factory: (inout Self) -> Void) -> Self {
    var copy = self
    factory(&copy)
    return copy
  }

  // MARK: Methods

  public mutating func handleElementAny(
    ids: [UInt]?, filter: Filter,
    rule: FilterRule
  ) -> Filter {
    guard let ids else {
      Logger.dataModel.error(
        "Invalid value for rule type or nil id \(String(describing: rule.ruleType)), \(String(describing: rule.value))"
      )
      remaining.append(rule)
      return filter
    }

    switch filter {
    case .anyOf(let existing):
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
      Logger.dataModel.error(
        "Invalid value for rule type or nil id \(String(describing: rule.ruleType)), \(String(describing: rule.value))"
      )
      remaining.append(rule)
      return filter
    }

    switch filter {
    case .noneOf(let existing):
      return .noneOf(ids: existing + ids)
    case .anyOf:
      Logger.dataModel.notice("Rule set combination invalid: anyOf + noneOf")
      fallthrough
    default:
      return .noneOf(ids: ids)
    }
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
    if customField != .any {
      result += 1
    }
    if asn != .any {
      result += 1
    }
    if date.isActive {
      result += 1
    }

    return result
  }

  public static func create(using factory: KeyPath<Self.Type, Self>, withRules rules: [FilterRule])
    -> Self
  {
    var state = Self.self[keyPath: factory]
    state.populateWith(rules: rules)
    return state
  }
}

// MARK: - DateFilter.Range RawRepresentable

extension FilterState.DateFilter.Range: RawRepresentable {
  public init?(rawValue: String) {
    // Try parsing rolling range: [-N component to now]
    if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
      // Strip brackets
      let inner = rawValue.dropFirst().dropLast()

      // Expected format: "-3 month to now"
      let parts = inner.split(separator: " ")
      guard parts.count == 4,
        parts[2] == "to",
        parts[3] == "now",
        let num = Int(parts[0])
      else {
        return nil
      }

      // Parse component (singular only)
      guard let component = FilterState.DateFilter.Component(rawValue: String(parts[1])) else {
        return nil
      }

      self = .within(num: num, interval: component)
      return
    }

    // Try parsing keyword range (lowercase only)
    switch rawValue {
    case "this year":
      self = .currentYear
    case "this month":
      self = .currentMonth
    case "today":
      self = .today
    case "yesterday":
      self = .yesterday
    case "previous week":
      self = .previousWeek
    case "previous month":
      self = .previousMonth
    case "previous quarter":
      self = .previousQuarter
    case "previous year":
      self = .previousYear
    default:
      return nil
    }
  }

  public var rawValue: String {
    switch self {
    case .within(let num, let interval):
      return "[\(num) \(interval.rawValue) to now]"
    case .currentYear:
      return "this year"
    case .currentMonth:
      return "this month"
    case .today:
      return "today"
    case .yesterday:
      return "yesterday"
    case .previousWeek:
      return "previous week"
    case .previousMonth:
      return "previous month"
    case .previousQuarter:
      return "previous quarter"
    case .previousYear:
      return "previous year"
    }
  }
}
