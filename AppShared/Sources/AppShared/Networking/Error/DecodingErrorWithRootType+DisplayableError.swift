//
//  DecodingErrorWithRootType+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//

import Networking

extension DecodingErrorWithRootType: DisplayableError {
  public var message: String {
    error.message
  }

  public var details: String? {
    error.makeDetails("\(type)")
  }
}
