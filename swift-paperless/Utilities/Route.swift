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

  public enum ParseError: Error, Equatable, Sendable {
    case invalidUrl
    case unsupportedVersion(String?)
    case missingPath
    case unknownResource(String)
    case missingDocumentId
    case invalidDocumentId(String)
    case missingAction
    case unknownAction(String)
    case invalidTagMode(String)
    case excludedTagsNotAllowedInAnyMode
  }

  public let action: Action
  public let server: String?

  public init(from url: URL) throws {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw ParseError.invalidUrl
    }

    guard let host = components.host else {
      throw ParseError.unsupportedVersion(nil)
    }

    guard host == "v1" else {
      throw ParseError.unsupportedVersion(host)
    }

    // Parse optional server from query string
    server = components.queryItems?.first(where: { $0.name == "server" })?.value

    var parts = components.path.split(separator: "/")

    guard parts.count >= 1 else {
      throw ParseError.missingPath
    }

    let resource = parts.removeFirst()

    switch resource {
    case "document":
      guard parts.count == 1 else {
        throw ParseError.missingDocumentId
      }

      let idString = String(parts.removeFirst())
      guard let id = UInt(idString) else {
        throw ParseError.invalidDocumentId(idString)
      }

      self.action = .document(id: id)

    case "action":
      guard parts.count == 1 else {
        throw ParseError.missingAction
      }
      let subaction = String(parts.removeFirst())
      switch subaction {
      case "scan":
        self.action = .scan
      case "set_filter":
        let tagFilter = try Self.parseTagFilter(from: components.queryItems ?? [])
        self.action = .setFilter(tags: tagFilter)
      default:
        throw ParseError.unknownAction(subaction)
      }
    default:
      throw ParseError.unknownResource(String(resource))
    }

  }

  static private func parseTagFilter(from queryItems: [URLQueryItem]) throws -> FilterState.TagFilter? {
    guard let tagQuery = queryItems.first(where: { $0.name == "tags" })?.value else {
      return nil
    }

    // Empty tags parameter means nil (don't change filter)
    guard !tagQuery.isEmpty else {
      return nil
    }

    let tagMode = queryItems.first(where: { $0.name == "tag_mode" })?.value ?? "any"

    guard tagMode == "any" || tagMode == "all" else {
      throw ParseError.invalidTagMode(tagMode)
    }

    switch tagQuery {
    case "none":
      return .notAssigned
    case "any":
      return .any
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
          throw ParseError.excludedTagsNotAllowedInAnyMode
        }
        return .anyOf(ids: include)
      case "all":
        return .allOf(include: include, exclude: exclude)
      default:
        throw ParseError.invalidTagMode(tagMode)
      }
    }
  }

}
