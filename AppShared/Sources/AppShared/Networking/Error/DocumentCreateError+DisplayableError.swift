//
//  DocumentCreateError+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.03.25.
//
import Networking

extension DocumentCreateError: DisplayableError {
  public var message: String {
    switch self {
    case .tooLarge:
      String(localized: .app(.documentCreateFailedTooLarge))
    }
  }

  public var details: String? {
    switch self {
    case .tooLarge:
      String(localized: .app(.documentCreateFailedTooLargeDetails))
    }
  }
}
