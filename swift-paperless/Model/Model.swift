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
            return "None"
        case .any:
            return "Any"
        case .all:
            return "All"
        case .literal:
            return "Exact"
        case .regex:
            return "RegEx"
        case .fuzzy:
            return "Fuzzy"
        case .auto:
            return "Auto"
        }
    }

    var label: String {
//        var result = title + ": "
        var result = ""
        switch self {
        case .none:
            result += "No automatic matching"
        case .any:
            result += "Document contains any of these words (space separated)"
        case .all:
            result += "Document contains all of these words (space separated)"
        case .literal:
            result += "Document contains this string"
        case .regex:
            result += "Document matches this regular expression"
        case .fuzzy:
            result += "Document contains a word similar to this word"
        case .auto:
            result += "Learn matching automatically"
        }
        return result
    }
}
