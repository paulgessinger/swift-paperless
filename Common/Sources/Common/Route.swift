//
//  Route.swift
//  Common
//
//  Created by Paul Gessinger on 04.01.26.
//

import Foundation

public struct Route: Equatable, Sendable {

  public enum Action: Equatable, Sendable {
    case document(id: UInt)
    case scan
  }

  public let action: Action
  public let server: String

  public init?(from: URL) {
    guard let components = URLComponents(url: from, resolvingAgainstBaseURL: false) else {
      return nil
    }

    guard components.host == "v1" else {
      return nil
    }

    var parts = components.path.split(separator: "/")

    guard parts.count >= 2 else {
      return nil
    }

    server = String(parts.removeFirst())
    guard !server.isEmpty else {
      return nil
    }

    let resource = parts.removeFirst()

    switch resource {
    case "document":
      guard parts.count == 1 else {
        return nil
      }

      guard let id = UInt(parts.removeFirst()) else {
        return nil
      }

      self.action = .document(id: id)

    case "action":
      guard parts.count == 1 else {
        return nil
      }
      let subaction = parts.removeFirst()
      switch subaction {
      case "scan":
        self.action = .scan
      default:
        return nil
      }
    default:
      return nil
    }

  }

}
