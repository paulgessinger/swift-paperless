//
//  Route.swift
//  Common
//
//  Created by Paul Gessinger on 04.01.26.
//

import DataModel
import Foundation

public struct Route: Equatable, Sendable {

  public enum Action: Equatable, Sendable {
    case document(id: UInt)
    case setFilter(tags: FilterState.TagFilter?)
    case scan
  }

  public let action: Action
  public let server: String?

  public init?(from: URL) {
    guard let components = URLComponents(url: from, resolvingAgainstBaseURL: false) else {
      return nil
    }

    guard components.host == "v1" else {
      return nil
    }

    // Parse optional server from query string
    server = components.queryItems?.first(where: { $0.name == "server" })?.value

    var parts = components.path.split(separator: "/")

    guard parts.count >= 1 else {
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
      case "set_filter":
        guard let tagFilter = Self.parseTagFilter(from: components.queryItems ?? []) else {
          return nil
        }
        self.action = .setFilter(tags: tagFilter)
      default:
        return nil
      }
    default:
      return nil
    }

  }

  static private func parseTagFilter(from queryItems: [URLQueryItem]) -> FilterState.TagFilter? {
    guard let tagQuery = queryItems.first(where: { $0.name == "tags" })?.value else {
      return .any
    }

    let tagMode = queryItems.first(where: { $0.name == "tag_mode" })?.value ?? "any"

    guard tagMode == "any" || tagMode == "all" else {
      return nil
    }

    switch tagQuery {
    case "none":
      return .notAssigned
    default:
      let tagStrings = tagQuery.split(separator: ",")
      var include = [UInt]()
      var exclude = [UInt]()
      for tagString in tagStrings {
        if tagString.hasPrefix("!"), let id = UInt(tagString.dropFirst()) {
          exclude.append(id)
          continue
        }

        if let id = UInt(tagString) {
          include.append(id)
        }
      }

      switch tagMode {
      case "any":
        guard exclude.isEmpty else {
          return nil  // Invalid
        }
        return .anyOf(ids: include)
      case "all":
        return .allOf(include: include, exclude: exclude)
      default:
        return nil
      }
    }
  }

}
