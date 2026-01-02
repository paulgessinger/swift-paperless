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
    result += fulltextQueryRules
    result += correspondentRules
    result += documentTypeRules
    result += storagePathRules
    result += tagRules
    result += ownerRules
    result += customFieldRules
    result += asnRules
    result += dateBetweenRules
    return result
  }

  private var searchRules: [FilterRule] {
    guard !searchText.isEmpty else { return [] }
    guard searchMode != .advanced else { return [] }
    return [FilterRule(ruleType: searchMode.ruleType, value: .string(value: searchText))!]
  }

  private var fulltextQueryRules: [FilterRule] {
    var components: [String] = []

    if searchMode == .advanced, !searchText.isEmpty {
      components.append(searchText)
    }

    if case .range(let range) = date.created {
      components.append("created:\(fulltextQueryValue(for: range))")
    }

    if case .range(let range) = date.added {
      components.append("added:\(fulltextQueryValue(for: range))")
    }

    guard !components.isEmpty else { return [] }
    let value = components.joined(separator: ",")
    return [FilterRule(ruleType: .fulltextQuery, value: .string(value: value))!]
  }

  private func fulltextQueryValue(for range: DateFilter.Range) -> String {
    switch range {
    case .within:
      return range.rawValue
    case .currentYear,
      .currentMonth,
      .today,
      .yesterday,
      .previousWeek,
      .previousMonth,
      .previousQuarter,
      .previousYear:
      return "\"\(range.rawValue)\""
    }
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

  private var dateBetweenRules: [FilterRule] {
    var result: [FilterRule] = []

    if case .between(let start, let end) = date.created {
      if let start {
        result.append(FilterRule(ruleType: .createdFrom, value: .date(value: start))!)
      }
      if let end {
        result.append(FilterRule(ruleType: .createdTo, value: .date(value: end))!)
      }
    }

    if case .between(let start, let end) = date.added {
      if let start {
        result.append(FilterRule(ruleType: .addedFrom, value: .date(value: start))!)
      }
      if let end {
        result.append(FilterRule(ruleType: .addedTo, value: .date(value: end))!)
      }
    }

    return result
  }
}
