//
//  MatchingAlgorithm.swift
//  DataModel
//
//  Created by Paul Gessinger on 18.12.2024.
//

public enum MatchingAlgorithm: Int, Codable, CaseIterable, Sendable {
  case none = 0
  case any = 1
  case all = 2
  case literal = 3
  case regex = 4
  case fuzzy = 5
  case auto = 6
}
