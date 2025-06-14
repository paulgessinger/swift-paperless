//
//  MatchingModel.swift
//  DataModel
//
//  Created by Paul Gessinger on 18.12.2024.
//

public protocol MatchingModel {
    var match: String { get set }
    var matchingAlgorithm: MatchingAlgorithm { get set }
    var isInsensitive: Bool { get set }
}
