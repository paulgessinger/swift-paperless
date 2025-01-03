//
//  MatchingAlgorithm.swift
//  DataModel
//
//  Created by Paul Gessinger on 18.12.2024.
//

public enum MatchingAlgorithm: Int, Codable, CaseIterable, Sendable {
    case none = 0, any = 1, all = 2, literal = 3, regex = 4, fuzzy = 5, auto = 6
}
