//
//  DocumentationLinks.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 27.04.2024.
//

import Foundation

struct DocumentationLinks {
  private init() {}

  static let baseUrl = URL(string: "https://swift-paperless.gessinger.dev")!

  static let localNetworkDenied = Self.baseUrl.appending(path: "common_issues/local-network-denied")

  static let forbidden = Self.baseUrl.appending(path: "common_issues/forbidden")

  static let insufficientPermissions = Self.baseUrl.appending(path: "common_issues/permissions")

  static let certificate = Self.baseUrl.appending(path: "common_issues/certificates")

  static let supportedVersions = Self.baseUrl.appending(path: "common_issues/supported-versions")
}
