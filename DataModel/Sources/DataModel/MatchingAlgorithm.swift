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
            String(localized: .localizable(.algorithmNone))
        case .any:
            String(localized: .localizable(.algorithmAny))
        case .all:
            String(localized: .localizable(.algorithmAll))
        case .literal:
            String(localized: .localizable(.algorithmExact))
        case .regex:
            String(localized: .localizable(.algorithmRegEx))
        case .fuzzy:
            String(localized: .localizable(.algorithmFuzzy))
        case .auto:
            String(localized: .localizable(.algorithmAuto))
        }
    }

    public var label: String {
        switch self {
        case .none:
            String(localized: .localizable(.explanationNone))
        case .any:
            String(localized: .localizable(.explanationAny))
        case .all:
            String(localized: .localizable(.explanationAny))
        case .literal:
            String(localized: .localizable(.explanationExact))
        case .regex:
            String(localized: .localizable(.explanationRegEx))
        case .fuzzy:
            String(localized: .localizable(.explanationFuzzy))
        case .auto:
            String(localized: .localizable(.explanationAuto))
        }
    }
}
