//
//  UrlError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.11.2024.
//

import Foundation

enum UrlError: LocalizedError, Equatable {
  case invalidScheme(_: String)
  case other
  case cannotSplit
  case emptyHost

  var errorDescription: String? {
    switch self {
    case .invalidScheme(let scheme):
      "Invalid scheme: \(scheme)"
    case .other: "other"
    case .cannotSplit: "cannot split"
    case .emptyHost: "empty host"
    }
  }
}
