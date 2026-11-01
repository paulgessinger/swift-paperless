//
//  DocumentationLinks.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 27.04.2024.
//

import Foundation

public struct DocumentationLinks {
  private init() {}

  public static let baseUrl = URL(string: "https://swift-paperless.app")!

  public static let localNetworkDenied = Self.baseUrl.appending(
    path: "common_issues/local-network-denied")

  public static let forbidden = Self.baseUrl.appending(path: "common_issues/forbidden")

  public static let insufficientPermissions = Self.baseUrl.appending(
    path: "common_issues/permissions")

  public static let certificate = Self.baseUrl.appending(path: "common_issues/certificates")

  public static let supportedVersions = Self.baseUrl.appending(
    path: "common_issues/supported-versions")

  public static let oidc = Self.baseUrl.appending(path: "oidc")

  public static let deeplinks = Self.baseUrl.appending(path: "deeplinks")

  // Trailing slash so relative links in release notes resolve inside this directory.
  public static let releaseNotes = Self.baseUrl.appending(path: "release_notes/")
}
