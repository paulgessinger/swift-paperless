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

protocol Model: Identifiable {
    var id: UInt { get }
}

protocol Named {
    var name: String { get }
}

enum MatchingAlgorithm: Int, Codable, CaseIterable {
    case none, any, all, literal, regex, fuzzy, auto

    var title: String {
        switch self {
        case .none:
            String(localized: .matching.algorithmNone)
        case .any:
            String(localized: .matching.algorithmAny)
        case .all:
            String(localized: .matching.algorithmAll)
        case .literal:
            String(localized: .matching.algorithmExact)
        case .regex:
            String(localized: .matching.algorithmRegEx)
        case .fuzzy:
            String(localized: .matching.algorithmFuzzy)
        case .auto:
            String(localized: .matching.algorithmAuto)
        }
    }

    var label: String {
        switch self {
        case .none:
            String(localized: .matching.explanationNone)
        case .any:
            String(localized: .matching.explanationAny)
        case .all:
            String(localized: .matching.explanationAny)
        case .literal:
            String(localized: .matching.explanationExact)
        case .regex:
            String(localized: .matching.explanationRegEx)
        case .fuzzy:
            String(localized: .matching.explanationFuzzy)
        case .auto:
            String(localized: .matching.explanationAuto)
        }
    }
}
