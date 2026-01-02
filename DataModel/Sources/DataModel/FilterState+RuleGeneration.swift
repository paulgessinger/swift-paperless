//
//  FilterState+RuleGeneration.swift
//  DataModel
//
//  Created by Claude on 02.01.26.
//

import Foundation

extension FilterState {
  public var rules: [FilterRule] {
    var result = remaining
    result += searchRules
    result += correspondentRules
    result += documentTypeRules
    result += storagePathRules
    result += tagRules
    result += ownerRules
    result += customFieldRules
    result += asnRules
    return result
  }

  private var searchRules: [FilterRule] {
    guard !searchText.isEmpty else { return [] }
    return [FilterRule(ruleType: searchMode.ruleType, value: .string(value: searchText))!]
  }

  private var correspondentRules: [FilterRule] {
    var result: [FilterRule] = []
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
    return result
  }

  private var documentTypeRules: [FilterRule] {
    var result: [FilterRule] = []
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
    return result
  }

  private var storagePathRules: [FilterRule] {
    var result: [FilterRule] = []
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
    return result
  }

  private var tagRules: [FilterRule] {
    var result: [FilterRule] = []
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
    return result
  }

  private var ownerRules: [FilterRule] {
    var result: [FilterRule] = []
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
    return result
  }

  private var customFieldRules: [FilterRule] {
    guard customField != .any else { return [] }
    return [FilterRule(ruleType: .customFieldsQuery, value: .customFieldQuery(customField))!]
  }

  private var asnRules: [FilterRule] {
    var result: [FilterRule] = []
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
}
