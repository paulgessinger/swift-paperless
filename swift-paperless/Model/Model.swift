//
//  Model.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import AsyncAlgorithms
import Foundation
import OrderedCollections
import SwiftUI

protocol MatchingModel {
    var match: String { get set }
    var matchingAlgorithm: MatchingAlgorithm { get set }
    var isInsensitive: Bool { get set }
}

protocol Model {
    var id: UInt { get }
}

enum MatchingAlgorithm: Int, Codable, CaseIterable {
    case none, any, all, literal, regex, fuzzy, auto

    var title: String {
        switch self {
        case .none:
            return String(localized:"None", comment: "Matching algorithm")
        case .any:
            return String(localized:"Any", comment: "Matching algorithm")
        case .all:
            return String(localized:"All", comment: "Matching algorithm")
        case .literal:
            return String(localized:"Exact", comment: "Matching algorithm")
        case .regex:
            return String(localized:"RegEx", comment: "Matching algorithm")
        case .fuzzy:
            return String(localized:"Fuzzy", comment: "Matching algorithm")
        case .auto:
            return String(localized:"Auto", comment: "Matching algorithm")
        }
    }

    var label: String {
        var result = ""
        switch self {
        case .none:
            result += String(localized: "matching_explanation_none", comment: "Matching algorithm")
        case .any:
            result += String(localized: "matching_explanation_any", comment: "Matching algorithm")
        case .all:
            result += String(localized: "matching_explanation_all", comment: "Matching algorithm")
        case .literal:
            result += String(localized: "matching_explanation_literal", comment: "Matching algorithm")
        case .regex:
            result += String(localized: "matching_explanation_regex", comment: "Matching algorithm")
        case .fuzzy:
            result += String(localized: "matching_explanation_fuzzy", comment: "Matching algorithm")
        case .auto:
            result += String(localized: "matching_explanation_auto", comment: "Matching algorithm")
        }
        return result
    }
}
