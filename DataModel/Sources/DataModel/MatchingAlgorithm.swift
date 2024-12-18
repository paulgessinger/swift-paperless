//
//  MatchingAlgorithm.swift
//  DataModel
//
//  Created by Paul Gessinger on 18.12.2024.
//

public enum MatchingAlgorithm: Int, Codable, CaseIterable, Sendable {
    case none, any, all, literal, regex, fuzzy, auto

    public var title: String {
        switch self {
        case .none:
            String(localized: .matching(.algorithmNone))
        case .any:
            String(localized: .matching(.algorithmAny))
        case .all:
            String(localized: .matching(.algorithmAll))
        case .literal:
            String(localized: .matching(.algorithmExact))
        case .regex:
            String(localized: .matching(.algorithmRegEx))
        case .fuzzy:
            String(localized: .matching(.algorithmFuzzy))
        case .auto:
            String(localized: .matching(.algorithmAuto))
        }
    }

    public var label: String {
        switch self {
        case .none:
            String(localized: .matching(.explanationNone))
        case .any:
            String(localized: .matching(.explanationAny))
        case .all:
            String(localized: .matching(.explanationAny))
        case .literal:
            String(localized: .matching(.explanationExact))
        case .regex:
            String(localized: .matching(.explanationRegEx))
        case .fuzzy:
            String(localized: .matching(.explanationFuzzy))
        case .auto:
            String(localized: .matching(.explanationAuto))
        }
    }
}
