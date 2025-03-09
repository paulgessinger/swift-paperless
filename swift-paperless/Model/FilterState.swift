//
//  FilterState.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.12.2024.
//

import Common
import DataModel
import Foundation
import os

// MARK: - FilterState

extension FilterState {
    private static var defaultSearchMode: SearchMode {
        AppSettings.value(for: .defaultSearchMode, or: .titleContent)
    }

    private static var defaultSortField: SortField {
        AppSettings.value(for: .defaultSortField, or: .added)
    }

    private static var defaultSortOrder: DataModel.SortOrder {
        AppSettings.value(for: .defaultSortOrder, or: .descending)
    }

    // MARK: Initializers

    static var `default`: Self {
        Self(
            correspondent: .any,
            documentType: .any,
            storagePath: .any,
            owner: .any,
            tags: .any,
            sortField: defaultSortField,
            sortOrder: defaultSortOrder,
            remaining: [],
            savedView: nil,
            searchText: nil,
            searchMode: defaultSearchMode
        )
    }

    init(savedView: SavedView) {
        self.init(rules: savedView.filterRules)
        self.savedView = savedView.id
        if let sortField = savedView.sortField {
            self.sortField = sortField
        }
        sortOrder = savedView.sortOrder
    }

    init(rules: [FilterRule]) {
        self = .default

        let getTagIds = { (rule: FilterRule) -> [UInt]? in
            switch rule.value {
            case let .tag(id):
                return [id]
            case let .invalid(value):
                Logger.shared.warning("Recovering multi-value rule \(String(describing: rule.ruleType), privacy: .public) from value \(String(describing: value), privacy: .public)")
                return value.components(separatedBy: ",").compactMap { UInt($0) }
            default:
                return nil
            }
        }

        let getOwnerIds = { (rule: FilterRule) -> [UInt]? in
            switch rule.value {
            case let .number(id):
                return [UInt(id)]
            case let .invalid(value):
                Logger.shared.warning("Recovering multi-value rule \(String(describing: rule.ruleType), privacy: .public) from value \(String(describing: value), privacy: .public)")
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
                guard case let .string(v) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }
                searchText = v

            case .correspondent:
                guard case let .correspondent(id) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                correspondent = id == nil ? .notAssigned : .anyOf(ids: [id!])

            case .hasCorrespondentAny:
                correspondent = handleElementAny(ids: rule.value.correspondentId,
                                                 filter: correspondent,
                                                 rule: rule)

            case .doesNotHaveCorrespondent:
                correspondent = handleElementNone(ids: rule.value.correspondentId,
                                                  filter: correspondent,
                                                  rule: rule)

            case .documentType:
                guard case let .documentType(id) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                documentType = id == nil ? .notAssigned : .anyOf(ids: [id!])

            case .hasDocumentTypeAny:
                documentType = handleElementAny(ids: rule.value.documentTypeId,
                                                filter: documentType,
                                                rule: rule)

            case .doesNotHaveDocumentType:
                documentType = handleElementNone(ids: rule.value.documentTypeId,
                                                 filter: documentType,
                                                 rule: rule)

            case .storagePath:
                guard case let .storagePath(id) = rule.value else {
                    Logger.shared.error("Invalid value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }
                storagePath = id == nil ? .notAssigned : .anyOf(ids: [id!])

            case .hasStoragePathAny:
                storagePath = handleElementAny(ids: rule.value.storagePathId,
                                               filter: storagePath,
                                               rule: rule)

            case .doesNotHaveStoragePath:
                storagePath = handleElementNone(ids: rule.value.storagePathId,
                                                filter: storagePath,
                                                rule: rule)

            case .hasTagsAll:
                guard let ids = getTagIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                if case let .allOf(include, exclude) = tags {
                    // have allOf already
                    tags = .allOf(include: include + ids, exclude: exclude)
                } else if case .any = tags {
                    tags = .allOf(include: ids, exclude: [])
                } else {
                    Logger.shared.error("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                }

            case .doesNotHaveTag:
                guard let ids = getTagIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                if case let .allOf(include, exclude) = tags {
                    // have allOf already
                    tags = .allOf(include: include, exclude: exclude + ids)
                } else if case .any = tags {
                    tags = .allOf(include: [], exclude: ids)
                } else {
                    Logger.shared.error("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                    break
                }

            case .hasTagsAny:
                guard let ruleIds = getTagIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                if case let .anyOf(ids) = tags {
                    tags = .anyOf(ids: ids + ruleIds)
                } else if case .any = tags {
                    tags = .anyOf(ids: ruleIds)
                } else {
                    Logger.shared.error("Already found .anyOf tag rule, inconsistent rule set?")
                    remaining.append(rule)
                    break
                }

            case .hasAnyTag:
                guard case let .boolean(value) = rule.value, value == false else {
                    print("Invalid value for rule type")
                    remaining.append(rule)
                    break
                }

                switch tags {
                case .anyOf:
                    fallthrough
                case .allOf:
                    print("Have filter state .allOf or .anyOf, but found is-not-tagged rule")
                    remaining.append(rule)
                case .any:
                    tags = .notAssigned
                case .notAssigned:
                    // nothing to do, redundant rule probably
                    break
                }

            case .owner:
                guard case let .number(id) = rule.value, id >= 0 else {
                    Logger.shared.error("Invalid value for rule type \(String(describing: rule.ruleType))")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case let .anyOf(ids):
                    if !(ids.count == 1 && ids[0] == id) {
                        Logger.shared.error("Owner is already set to .anyOf, but got other owner")
                    }
                    fallthrough // reset anyway
                case .noneOf:
                    Logger.shared.error("Owner is already set to .noneOf, but got explicit owner")
                    fallthrough // reset anyway
                case .notAssigned:
                    Logger.shared.error("Already have ownerIsnull rule, but got explicit owner")
                    fallthrough // reset anyway
                case .any:
                    owner = .anyOf(ids: [UInt(id)])
                }

            case .ownerIsnull:
                guard case let .boolean(value) = rule.value else {
                    Logger.shared.error("Invalid value for rule type \(String(describing: rule.ruleType))")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case .anyOf:
                    Logger.shared.error("Owner is already set to .anyOf, but got ownerIsnull=\(value)")
                    fallthrough // reset anyway
                case .noneOf:
                    Logger.shared.error("Owner is already set to .noneOf, but got ownerIsnull=\(value)")
                    fallthrough // reset anyway
                case .notAssigned:
                    Logger.shared.error("Already have ownerIsnull rule, but got ownerIsnull=\(value)")
                    fallthrough // reset anyway
                case .any:
                    owner = value ? .notAssigned : .any
                }

            case .ownerAny:
                guard let ids = getOwnerIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case let .anyOf(existing):
                    owner = .anyOf(ids: existing + ids)
                case .noneOf, .notAssigned:
                    let ownerCopy = owner
                    Logger.shared.error("Owner is already set to \(String(describing: ownerCopy)), but got rule ownerAny=\(ids)")
                    fallthrough // reset anyway
                case .any:
                    owner = .anyOf(ids: ids)
                }

            case .ownerDoesNotInclude:
                guard let ids = getOwnerIds(rule) else {
                    Logger.shared.error("Cannot handle value \(String(describing: rule.value)) for rule type \(String(describing: rule.ruleType), privacy: .public)")
                    remaining.append(rule)
                    break
                }

                switch owner {
                case let .noneOf(existing):
                    owner = .noneOf(ids: existing + ids)
                case .anyOf, .notAssigned:
                    let ownerCopy = owner
                    Logger.shared.error("Owner is already set to \(String(describing: ownerCopy)), but got rule ownerDoesNotInclude=\(ids)")
                    fallthrough // reset anyway
                case .any:
                    owner = .noneOf(ids: ids)
                }

            default:
                remaining.append(rule)
            }
        }
    }

    var defaultSorting: Bool {
        sortField == Self.defaultSortField && sortOrder == Self.defaultSortOrder
    }

    // MARK: Methods

    mutating func clear() {
        self = FilterState.default
    }

    var filtering: Bool {
        ruleCount > 0 || !defaultSorting
    }
}
