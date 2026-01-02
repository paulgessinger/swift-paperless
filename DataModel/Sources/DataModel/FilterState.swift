//
//  FilterState.swift
//  DataModel
//
//  Created by Paul Gessinger on 09.03.25.
//

import Common
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

  public var rules: [FilterRule] {
    var result = remaining

    if !searchText.isEmpty {
      result.append(
        FilterRule(ruleType: searchMode.ruleType, value: .string(value: searchText))!
      )
    }

    switch correspondent {
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .correspondent, value: .correspondent(id: nil))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: id))!
        )
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .doesNotHaveCorrespondent, value: .correspondent(id: id))!
        )
      }
    case .any: break
    }

    switch documentType {
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .documentType, value: .documentType(id: nil))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: id))!
        )
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .doesNotHaveDocumentType, value: .documentType(id: id))!
        )
      }
    case .any: break
    }

    switch storagePath {
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .storagePath, value: .storagePath(id: nil))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasStoragePathAny, value: .storagePath(id: id))!
        )
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .doesNotHaveStoragePath, value: .storagePath(id: id))!
        )
      }
    case .any: break
    }

    switch tags {
    case .any: break
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .hasAnyTag, value: .boolean(value: false))!
      )
    case .allOf(let include, let exclude):
      for id in include {
        result.append(
          FilterRule(ruleType: .hasTagsAll, value: .tag(id: id))!
        )
      }
      for id in exclude {
        result.append(
          FilterRule(ruleType: .doesNotHaveTag, value: .tag(id: id))!
        )
      }
    case .anyOf(let ids):
      for id in ids {
        result.append(
          FilterRule(ruleType: .hasTagsAny, value: .tag(id: id))!
        )
      }
    }

    switch owner {
    case .any: break
    case .notAssigned:
      result.append(
        FilterRule(ruleType: .ownerIsnull, value: .boolean(value: true))!
      )
    case .anyOf(let ids):
      for id in ids {
        result.append(FilterRule(ruleType: .ownerAny, value: .number(value: Int(id)))!)
      }
    case .noneOf(let ids):
      for id in ids {
        result.append(FilterRule(ruleType: .ownerDoesNotInclude, value: .number(value: Int(id)))!)
      }
    }

    if customField != .any {
      result.append(
        FilterRule(ruleType: .customFieldsQuery, value: .customFieldQuery(customField))!
      )
    }

    switch asn {
    case .any: break
    case .isNull:
      result.append(
        FilterRule(ruleType: .asnIsnull, value: .boolean(value: true))!
      )
    case .isNotNull:
      result.append(
        FilterRule(ruleType: .asnIsnull, value: .boolean(value: false))!
      )
    case .equalTo(let value):
      result.append(
        FilterRule(ruleType: .asn, value: .number(value: Int(value)))!
      )
    case .greaterThan(let value):
      result.append(
        FilterRule(ruleType: .asnGt, value: .number(value: Int(value)))!
      )
    case .lessThan(let value):
      result.append(
        FilterRule(ruleType: .asnLt, value: .number(value: Int(value)))!
      )
    }

    return result
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

    return result
  }

  public static func create(using factory: KeyPath<Self.Type, Self>, withRules rules: [FilterRule])
    -> Self
  {
    var state = Self.self[keyPath: factory]
    state.populateWith(rules: rules)
    return state
  }

  private mutating func populateWith(rules: [FilterRule]) {
    let getTagIds = { (rule: FilterRule) -> [UInt]? in
      switch rule.value {
      case .tag(let id):
        return [id]
      case .invalid(let value):
        Logger.dataModel.warning(
          "Recovering multi-value rule \(String(describing: rule.ruleType), privacy: .public) from value \(String(describing: value), privacy: .public)"
        )
        return value.components(separatedBy: ",").compactMap { UInt($0) }
      default:
        return nil
      }
    }

    let getOwnerIds = { (rule: FilterRule) -> [UInt]? in
      switch rule.value {
      case .number(let id):
        return [UInt(id)]
      case .invalid(let value):
        Logger.dataModel.warning(
          "Recovering multi-value rule \(String(describing: rule.ruleType), privacy: .public) from value \(String(describing: value), privacy: .public)"
        )
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
        guard case .string(let v) = rule.value else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }
        searchText = v

      case .correspondent:
        guard case .correspondent(let id) = rule.value else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        correspondent = id == nil ? .notAssigned : .anyOf(ids: [id!])

      case .hasCorrespondentAny:
        correspondent = handleElementAny(
          ids: rule.value.correspondentId,
          filter: correspondent,
          rule: rule)

      case .doesNotHaveCorrespondent:
        correspondent = handleElementNone(
          ids: rule.value.correspondentId,
          filter: correspondent,
          rule: rule)

      case .documentType:
        guard case .documentType(let id) = rule.value else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        documentType = id == nil ? .notAssigned : .anyOf(ids: [id!])

      case .hasDocumentTypeAny:
        documentType = handleElementAny(
          ids: rule.value.documentTypeId,
          filter: documentType,
          rule: rule)

      case .doesNotHaveDocumentType:
        documentType = handleElementNone(
          ids: rule.value.documentTypeId,
          filter: documentType,
          rule: rule)

      case .storagePath:
        guard case .storagePath(let id) = rule.value else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }
        storagePath = id == nil ? .notAssigned : .anyOf(ids: [id!])

      case .hasStoragePathAny:
        storagePath = handleElementAny(
          ids: rule.value.storagePathId,
          filter: storagePath,
          rule: rule)

      case .doesNotHaveStoragePath:
        storagePath = handleElementNone(
          ids: rule.value.storagePathId,
          filter: storagePath,
          rule: rule)

      case .hasTagsAll:
        guard let ids = getTagIds(rule) else {
          Logger.dataModel.error(
            "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        if case .allOf(let include, let exclude) = tags {
          // have allOf already
          tags = .allOf(include: include + ids, exclude: exclude)
        } else if case .any = tags {
          tags = .allOf(include: ids, exclude: [])
        } else {
          Logger.dataModel.error("Already found .anyOf tag rule, inconsistent rule set?")
          remaining.append(rule)
        }

      case .doesNotHaveTag:
        guard let ids = getTagIds(rule) else {
          Logger.dataModel.error(
            "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        if case .allOf(let include, let exclude) = tags {
          // have allOf already
          tags = .allOf(include: include, exclude: exclude + ids)
        } else if case .any = tags {
          tags = .allOf(include: [], exclude: ids)
        } else {
          Logger.dataModel.error("Already found .anyOf tag rule, inconsistent rule set?")
          remaining.append(rule)
          break
        }

      case .hasTagsAny:
        guard let ruleIds = getTagIds(rule) else {
          Logger.dataModel.error(
            "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        if case .anyOf(let ids) = tags {
          tags = .anyOf(ids: ids + ruleIds)
        } else if case .any = tags {
          tags = .anyOf(ids: ruleIds)
        } else {
          Logger.dataModel.error("Already found .anyOf tag rule, inconsistent rule set?")
          remaining.append(rule)
          break
        }

      case .hasAnyTag:
        guard case .boolean(let value) = rule.value, value == false else {
          Logger.dataModel.error("Invalid value for rule type")
          remaining.append(rule)
          break
        }

        switch tags {
        case .anyOf, .allOf:
          Logger.dataModel.error("Have filter state .allOf or .anyOf, but found is-not-tagged rule")
          remaining.append(rule)
        case .any:
          tags = .notAssigned
        case .notAssigned:
          // nothing to do, redundant rule probably
          break
        }

      case .owner:
        guard case .number(let id) = rule.value, id >= 0 else {
          Logger.dataModel.error("Invalid value for rule type \(String(describing: rule.ruleType))")
          remaining.append(rule)
          break
        }

        switch owner {
        case .anyOf(let ids):
          if !(ids.count == 1 && ids[0] == id) {
            Logger.dataModel.error("Owner is already set to .anyOf, but got other owner")
          }
          fallthrough  // reset anyway
        case .noneOf:
          Logger.dataModel.error("Owner is already set to .noneOf, but got explicit owner")
          fallthrough  // reset anyway
        case .notAssigned:
          Logger.dataModel.error("Already have ownerIsnull rule, but got explicit owner")
          fallthrough  // reset anyway
        case .any:
          owner = .anyOf(ids: [UInt(id)])
        }

      case .ownerIsnull:
        guard case .boolean(let value) = rule.value else {
          Logger.dataModel.error("Invalid value for rule type \(String(describing: rule.ruleType))")
          remaining.append(rule)
          break
        }

        switch owner {
        case .anyOf:
          Logger.dataModel.error("Owner is already set to .anyOf, but got ownerIsnull=\(value)")
          fallthrough  // reset anyway
        case .noneOf:
          Logger.dataModel.error("Owner is already set to .noneOf, but got ownerIsnull=\(value)")
          fallthrough  // reset anyway
        case .notAssigned:
          Logger.dataModel.error("Already have ownerIsnull rule, but got ownerIsnull=\(value)")
          fallthrough  // reset anyway
        case .any:
          owner = value ? .notAssigned : .any
        }

      case .ownerAny:
        guard let ids = getOwnerIds(rule) else {
          Logger.dataModel.error(
            "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        switch owner {
        case .anyOf(let existing):
          owner = .anyOf(ids: existing + ids)
        case .noneOf, .notAssigned:
          let ownerCopy = owner
          Logger.dataModel.error(
            "Owner is already set to \(String(describing: ownerCopy)), but got rule ownerAny=\(ids)"
          )
          fallthrough  // reset anyway
        case .any:
          owner = .anyOf(ids: ids)
        }

      case .ownerDoesNotInclude:
        guard let ids = getOwnerIds(rule) else {
          Logger.dataModel.error(
            "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        switch owner {
        case .noneOf(let existing):
          owner = .noneOf(ids: existing + ids)
        case .anyOf, .notAssigned:
          let ownerCopy = owner
          Logger.dataModel.error(
            "Owner is already set to \(String(describing: ownerCopy)), but got rule ownerDoesNotInclude=\(ids)"
          )
          fallthrough  // reset anyway
        case .any:
          owner = .noneOf(ids: ids)
        }

      case .customFieldsQuery:
        guard case .customFieldQuery(let query) = rule.value else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        customField = query

      case .asn:
        guard case .number(let value) = rule.value, value >= 0 else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        switch asn {
        case .equalTo(let existing):
          if existing != value {
            Logger.dataModel.error(
              "ASN is already set to .equalTo(\(existing, privacy: .public)), but got .asn=\(value, privacy: .public)"
            )
          }
          fallthrough  // reset anyway
        case .greaterThan, .lessThan:
          Logger.dataModel.error(
            "ASN is already set to comparison filter, but got explicit asn=\(value, privacy: .public)"
          )
          fallthrough  // reset anyway
        case .isNull, .isNotNull:
          Logger.dataModel.error(
            "ASN is already set to null check, but got explicit asn=\(value, privacy: .public)")
          fallthrough  // reset anyway
        case .any:
          asn = .equalTo(UInt(value))
        }

      case .asnIsnull:
        guard case .boolean(let value) = rule.value else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        switch asn {
        case .equalTo, .greaterThan, .lessThan:
          Logger.dataModel.error(
            "ASN is already set to a value filter, but got asnIsnull=\(value, privacy: .public)")
          fallthrough  // reset anyway
        case .isNull, .isNotNull:
          Logger.dataModel.error(
            "Already have asnIsnull rule, but got asnIsnull=\(value, privacy: .public)")
          fallthrough  // reset anyway
        case .any:
          asn = value ? .isNull : .isNotNull
        }

      case .asnGt:
        guard case .number(let value) = rule.value, value >= 0 else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        switch asn {
        case .greaterThan(let existing):
          if existing != value {
            Logger.dataModel.error(
              "ASN is already set to .greaterThan(\(existing, privacy: .public)), but got .asnGt=\(value, privacy: .public)"
            )
          }
          fallthrough  // reset anyway
        case .equalTo, .lessThan:
          Logger.dataModel.error(
            "ASN is already set to different filter, but got asnGt=\(value, privacy: .public)")
          fallthrough  // reset anyway
        case .isNull, .isNotNull:
          Logger.dataModel.error(
            "ASN is already set to null check, but got asnGt=\(value, privacy: .public)")
          fallthrough  // reset anyway
        case .any:
          asn = .greaterThan(UInt(value))
        }

      case .asnLt:
        guard case .number(let value) = rule.value, value >= 0 else {
          Logger.dataModel.error(
            "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
          )
          remaining.append(rule)
          break
        }

        switch asn {
        case .lessThan(let existing):
          if existing != value {
            Logger.dataModel.error(
              "ASN is already set to .lessThan(\(existing)), but got .asnLt=\(value)")
          }
          fallthrough  // reset anyway
        case .equalTo, .greaterThan:
          Logger.dataModel.error("ASN is already set to different filter, but got asnLt=\(value)")
          fallthrough  // reset anyway
        case .isNull, .isNotNull:
          Logger.dataModel.error("ASN is already set to null check, but got asnLt=\(value)")
          fallthrough  // reset anyway
        case .any:
          asn = .lessThan(UInt(value))
        }

      default:
        remaining.append(rule)
      }
    }
  }
}
