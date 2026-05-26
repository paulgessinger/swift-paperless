//
//  URL+Extensions.swift
//  Common
//
//  Created by Paul Gessinger on 04.01.26.
//

import Foundation

extension URL {
  public var stringDroppingScheme: String? {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
      return nil
    }

    guard components.scheme != nil else {
      return absoluteString
    }

    components.scheme = nil

    guard let resultURL = components.url else {
      return nil
    }

    let result = resultURL.absoluteString
    // Remove leading "//" that remains after removing scheme
    if result.hasPrefix("//") {
      return String(result.dropFirst(2))
    }

    return result
  }
}
