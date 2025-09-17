//
//  Sanitize.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.03.25.
//

import Foundation

public func sanitize(headers: [String: String]?) -> String {
  if let headers {
    #if DEBUG
      return "\(headers)"
    #else
      return headers.map { key, value in
        "\(key): <len:\(value.count)>"
      }.joined(separator: ", ")
    #endif
  } else {
    return "<no headers>"
  }
}

public func sanitize(token: String?) -> String {
  guard let token else { return "nil" }
  #if DEBUG
    return token
  #else
    return "<token len: \(token.count)>"
  #endif
}
