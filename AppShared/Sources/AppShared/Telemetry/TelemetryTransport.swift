//
//  TelemetryTransport.swift
//  AppShared
//

import Foundation

/// Delivers one encoded ping. Throws on any failure; the caller drops it.
public protocol TelemetryTransport: Sendable {
  func send(_ body: Data, to endpoint: TelemetryEndpoint) async throws
}

/// POSTs to the collector over an ephemeral session: no cookies, no cache, no
/// credentials, a static User-Agent and no `Accept-Language`.
public struct URLSessionTelemetryTransport: TelemetryTransport {
  public struct HTTPStatusError: Error {
    public let status: Int
  }

  private static let userAgent = "swift-paperless-telemetry"

  private let baseURL: URL
  private let session: URLSession

  public init(baseURL: URL) {
    self.baseURL = baseURL

    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieAcceptPolicy = .never
    configuration.httpShouldSetCookies = false
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30
    configuration.waitsForConnectivity = false
    // Replaces URLSession's default `User-Agent` (app name, build, CFNetwork
    // and Darwin versions) and `Accept-Language` (the user's region).
    configuration.httpAdditionalHeaders = [
      "User-Agent": Self.userAgent,
      "Accept-Language": "*",
    ]
    session = URLSession(configuration: configuration)
  }

  public func send(_ body: Data, to endpoint: TelemetryEndpoint) async throws {
    var request = URLRequest(url: baseURL.appending(path: endpoint.path))
    request.httpMethod = "POST"
    request.httpBody = body
    request.httpShouldHandleCookies = false
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("*", forHTTPHeaderField: "Accept-Language")

    let (_, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw HTTPStatusError(status: http.statusCode)
    }
  }
}
