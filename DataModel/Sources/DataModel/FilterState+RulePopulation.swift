//
//  FilterState+RulePopulation.swift
//  DataModel
//
//  Created by Claude on 02.01.26.
//

import Common
import Foundation
import os

extension FilterState {
  internal mutating func populateWith(rules: [FilterRule]) {
    for rule in rules {
      switch rule.ruleType {
      case .title, .content, .titleContent, .fulltextQuery:
        handleSearchRule(rule)
      case .correspondent:
        handleCorrespondentRule(rule)
      case .hasCorrespondentAny:
        handleCorrespondentAnyRule(rule)
      case .doesNotHaveCorrespondent:
        handleCorrespondentNoneRule(rule)
      case .documentType:
        handleDocumentTypeRule(rule)
      case .hasDocumentTypeAny:
        handleDocumentTypeAnyRule(rule)
      case .doesNotHaveDocumentType:
        handleDocumentTypeNoneRule(rule)
      case .storagePath:
        handleStoragePathRule(rule)
      case .hasStoragePathAny:
        handleStoragePathAnyRule(rule)
      case .doesNotHaveStoragePath:
        handleStoragePathNoneRule(rule)
      case .hasTagsAll:
        handleTagsAllRule(rule)
      case .doesNotHaveTag:
        handleDoesNotHaveTagRule(rule)
      case .hasTagsAny:
        handleTagsAnyRule(rule)
      case .hasAnyTag:
        handleHasAnyTagRule(rule)
      case .owner:
        handleOwnerRule(rule)
      case .ownerIsnull:
        handleOwnerIsnullRule(rule)
      case .ownerAny:
        handleOwnerAnyRule(rule)
      case .ownerDoesNotInclude:
        handleOwnerDoesNotIncludeRule(rule)
      case .customFieldsQuery:
        handleCustomFieldsQueryRule(rule)
      case .asn:
        handleAsnRule(rule)
      case .asnIsnull:
        handleAsnIsnullRule(rule)
      case .asnGt:
        handleAsnGtRule(rule)
      case .asnLt:
        handleAsnLtRule(rule)
      default:
        remaining.append(rule)
      }
    }
  }

  // MARK: - Search Rule Handlers

  private mutating func handleSearchRule(_ rule: FilterRule) {
    guard let mode = SearchMode(ruleType: rule.ruleType) else {
      fatalError("Could not convert rule type to search mode (this should not occur)")
    }
    searchMode = mode
    guard case .string(let v) = rule.value else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }
    searchText = v
  }

  // MARK: - Correspondent Rule Handlers

  private mutating func handleCorrespondentRule(_ rule: FilterRule) {
    guard case .correspondent(let id) = rule.value else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }

    correspondent = id == nil ? .notAssigned : .anyOf(ids: [id!])
  }

  private mutating func handleCorrespondentAnyRule(_ rule: FilterRule) {
    correspondent = handleElementAny(
      ids: rule.value.correspondentId,
      filter: correspondent,
      rule: rule)
  }

  private mutating func handleCorrespondentNoneRule(_ rule: FilterRule) {
    correspondent = handleElementNone(
      ids: rule.value.correspondentId,
      filter: correspondent,
      rule: rule)
  }

  // MARK: - Document Type Rule Handlers

  private mutating func handleDocumentTypeRule(_ rule: FilterRule) {
    guard case .documentType(let id) = rule.value else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }

    documentType = id == nil ? .notAssigned : .anyOf(ids: [id!])
  }

  private mutating func handleDocumentTypeAnyRule(_ rule: FilterRule) {
    documentType = handleElementAny(
      ids: rule.value.documentTypeId,
      filter: documentType,
      rule: rule)
  }

  private mutating func handleDocumentTypeNoneRule(_ rule: FilterRule) {
    documentType = handleElementNone(
      ids: rule.value.documentTypeId,
      filter: documentType,
      rule: rule)
  }

  // MARK: - Storage Path Rule Handlers

  private mutating func handleStoragePathRule(_ rule: FilterRule) {
    guard case .storagePath(let id) = rule.value else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }
    storagePath = id == nil ? .notAssigned : .anyOf(ids: [id!])
  }

  private mutating func handleStoragePathAnyRule(_ rule: FilterRule) {
    storagePath = handleElementAny(
      ids: rule.value.storagePathId,
      filter: storagePath,
      rule: rule)
  }

  private mutating func handleStoragePathNoneRule(_ rule: FilterRule) {
    storagePath = handleElementNone(
      ids: rule.value.storagePathId,
      filter: storagePath,
      rule: rule)
  }

  // MARK: - Tag Rule Handlers

  private mutating func handleTagsAllRule(_ rule: FilterRule) {
    guard let ids = rule.value.tagIds else {
      Logger.dataModel.error(
        "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }

  private mutating func handleDoesNotHaveTagRule(_ rule: FilterRule) {
    guard let ids = rule.value.tagIds else {
      Logger.dataModel.error(
        "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }

    if case .allOf(let include, let exclude) = tags {
      // have allOf already
      tags = .allOf(include: include, exclude: exclude + ids)
    } else if case .any = tags {
      tags = .allOf(include: [], exclude: ids)
    } else {
      Logger.dataModel.error("Already found .anyOf tag rule, inconsistent rule set?")
      remaining.append(rule)
      return
    }
  }

  private mutating func handleTagsAnyRule(_ rule: FilterRule) {
    guard let ruleIds = rule.value.tagIds else {
      Logger.dataModel.error(
        "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }

    if case .anyOf(let ids) = tags {
      tags = .anyOf(ids: ids + ruleIds)
    } else if case .any = tags {
      tags = .anyOf(ids: ruleIds)
    } else {
      Logger.dataModel.error("Already found .anyOf tag rule, inconsistent rule set?")
      remaining.append(rule)
      return
    }
  }

  private mutating func handleHasAnyTagRule(_ rule: FilterRule) {
    guard case .boolean(let value) = rule.value, value == false else {
      Logger.dataModel.error("Invalid value for rule type")
      remaining.append(rule)
      return
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
  }

  // MARK: - Owner Rule Handlers

  private mutating func handleOwnerRule(_ rule: FilterRule) {
    guard case .number(let id) = rule.value, id >= 0 else {
      Logger.dataModel.error("Invalid value for rule type \(String(describing: rule.ruleType))")
      remaining.append(rule)
      return
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
  }

  private mutating func handleOwnerIsnullRule(_ rule: FilterRule) {
    guard case .boolean(let value) = rule.value else {
      Logger.dataModel.error("Invalid value for rule type \(String(describing: rule.ruleType))")
      remaining.append(rule)
      return
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
  }

  private mutating func handleOwnerAnyRule(_ rule: FilterRule) {
    guard let ids = rule.value.ownerIds else {
      Logger.dataModel.error(
        "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }

  private mutating func handleOwnerDoesNotIncludeRule(_ rule: FilterRule) {
    guard let ids = rule.value.ownerIds else {
      Logger.dataModel.error(
        "Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }

  // MARK: - Custom Field Rule Handler

  private mutating func handleCustomFieldsQueryRule(_ rule: FilterRule) {
    guard case .customFieldQuery(let query) = rule.value else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
    }

    customField = query
  }

  // MARK: - ASN Rule Handlers

  private mutating func handleAsnRule(_ rule: FilterRule) {
    guard case .number(let value) = rule.value, value >= 0 else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }

  private mutating func handleAsnIsnullRule(_ rule: FilterRule) {
    guard case .boolean(let value) = rule.value else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }

  private mutating func handleAsnGtRule(_ rule: FilterRule) {
    guard case .number(let value) = rule.value, value >= 0 else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }

  private mutating func handleAsnLtRule(_ rule: FilterRule) {
    guard case .number(let value) = rule.value, value >= 0 else {
      Logger.dataModel.error(
        "Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)"
      )
      remaining.append(rule)
      return
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
  }
}
