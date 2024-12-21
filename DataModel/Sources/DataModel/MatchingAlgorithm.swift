//
//  MatchingAlgorithm.swift
//  DataModel
//
//  Created by Paul Gessinger on 18.12.2024.
//

public enum MatchingAlgorithm: Int, Codable, CaseIterable, Sendable {
    case none, any, all, literal, regex, fuzzy, auto
}
