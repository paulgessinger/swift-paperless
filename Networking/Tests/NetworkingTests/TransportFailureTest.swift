//
//  TransportFailureTest.swift
//  Networking
//
//  Device-offline vs. server-unreachable: the classification table, and how
//  `RequestError(from:)` maps URL error codes onto it.
//

import Common
import Foundation
import Testing

@testable import Networking

@Suite struct TransportFailureTest {
  private static func urlError(
    code: Int, description: String = "Could not connect to the server.",
    failingURL: String = "https://example.com/api/documents/"
  ) -> NSError {
    NSError(
      domain: NSURLErrorDomain, code: code,
      userInfo: [
        NSLocalizedDescriptionKey: description,
        NSURLErrorFailingURLStringErrorKey: failingURL,
      ])
  }

  static let deviceSideCodes: [NSURLError] = [
    .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
  ]
  static let hostNotFoundCodes: [NSURLError] = [.cannotFindHost, .dnsLookupFailed]
  static let notRespondingCodes: [NSURLError] = [.cannotConnectToHost, .timedOut]
  static let connectivityCodes: [NSURLError] =
    deviceSideCodes + hostNotFoundCodes + notRespondingCodes + [.networkConnectionLost]

  // MARK: - The table

  @Test(
    "No network path means offline, whatever the code",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/667", id: 667),
    arguments: connectivityCodes)
  func unsatisfiedPathIsOffline(code: NSURLError) {
    #expect(TransportFailureKind(code: code, path: .unsatisfied) == .offline)
  }

  @Test(arguments: [NetworkPathStatus.satisfied, .unknown], hostNotFoundCodes)
  func unresolvableHostWhileOnline(path: NetworkPathStatus, code: NSURLError) {
    #expect(TransportFailureKind(code: code, path: path) == .hostNotFound)
  }

  @Test(arguments: [NetworkPathStatus.satisfied, .unknown], notRespondingCodes)
  func noAnswerWhileOnline(path: NetworkPathStatus, code: NSURLError) {
    #expect(TransportFailureKind(code: code, path: path) == .serverNotResponding)
  }

  @Test(arguments: [NetworkPathStatus.satisfied, .unknown])
  func droppedConnectionWhileOnline(path: NetworkPathStatus) {
    #expect(TransportFailureKind(code: .networkConnectionLost, path: path) == .connectionLost)
  }

  // The path monitor lags the interface; URLSession saying "not connected" is
  // the more direct evidence, so it wins over a (stale) satisfied path.
  @Test(arguments: [NetworkPathStatus.satisfied, .unknown], deviceSideCodes)
  func deviceSideCodesAreOfflineEvenOnASatisfiedPath(path: NetworkPathStatus, code: NSURLError) {
    #expect(TransportFailureKind(code: code, path: path) == .offline)
  }

  @Test(
    arguments: [
      NSURLError.cancelled, .badURL, .unsupportedURL, .httpTooManyRedirects,
      .redirectToNonExistentLocation, .badServerResponse, .resourceUnavailable,
      .serverCertificateUntrusted, .cannotWriteToFile, .unknown,
    ])
  func otherCodesAreNotConnectivity(code: NSURLError) {
    #expect(TransportFailureKind(code: code, path: .unsatisfied) == nil)
    #expect(TransportFailureKind(code: code, path: .satisfied) == nil)
  }

  // MARK: - RequestError(from:path:)

  @Test
  func preservesCodeKindAndDetail() throws {
    let error = try #require(
      RequestError(
        from: Self.urlError(code: NSURLErrorCannotFindHost, description: "Host not found"),
        path: .satisfied))
    #expect(
      error == .connectivity(code: .cannotFindHost, kind: .hostNotFound, detail: "Host not found"))
  }

  @Test
  func classifiesAgainstThePathItIsGiven() throws {
    let raw = Self.urlError(code: NSURLErrorCannotConnectToHost)

    let online = try #require(RequestError(from: raw, path: .satisfied))
    let offline = try #require(RequestError(from: raw, path: .unsatisfied))

    guard case .connectivity(_, let onlineKind, _) = online,
      case .connectivity(_, let offlineKind, _) = offline
    else {
      Issue.record("Expected .connectivity, got \(online) / \(offline)")
      return
    }
    #expect(onlineKind == .serverNotResponding)
    #expect(offlineKind == .offline)
  }

  // Timeouts used to fall through to `nil` and reach the login screen as an
  // unrecognised error; they are a server-not-responding failure.
  @Test
  func timeoutIsConnectivity() throws {
    let error = try #require(
      RequestError(from: Self.urlError(code: NSURLErrorTimedOut), path: .satisfied))
    guard case .connectivity(.timedOut, .serverNotResponding, _) = error else {
      Issue.record("Expected .connectivity(timedOut, serverNotResponding), got \(error)")
      return
    }
  }

  // One outage against two endpoints is one error value: the raw NSErrors
  // differ (failing URL in userInfo), the normalized errors don't.
  @Test
  func sameOutageOnDifferentEndpointsIsOneError() throws {
    let metadata = Self.urlError(
      code: NSURLErrorCannotConnectToHost,
      failingURL: "https://example.com/api/documents/1/metadata/")
    let notes = Self.urlError(
      code: NSURLErrorCannotConnectToHost, failingURL: "https://example.com/api/documents/1/notes/")
    #expect(metadata != notes)
    #expect(
      RequestError(from: metadata, path: .satisfied) == RequestError(from: notes, path: .satisfied))
  }

  @Test
  func sslFailuresAreCertificateErrors() throws {
    let error = try #require(
      RequestError(
        from: Self.urlError(code: NSURLErrorServerCertificateUntrusted, description: "untrusted"),
        path: .satisfied))
    #expect(error == .certificate(detail: "untrusted"))
  }

  @Test(
    arguments: [
      NSURLErrorBadURL, NSURLErrorUnsupportedURL, NSURLErrorHTTPTooManyRedirects,
      NSURLErrorRedirectToNonExistentLocation, NSURLErrorBadServerResponse,
      NSURLErrorResourceUnavailable,
    ])
  func nonReachabilityCodesStayOther(code: Int) throws {
    let error = try #require(
      RequestError(
        from: Self.urlError(code: code, description: "system message"), path: .unsatisfied))
    #expect(error == .other("system message"))
  }

  @Test(arguments: [
    NSURLErrorCancelled, NSURLErrorCannotWriteToFile, NSURLErrorCannotParseResponse,
  ])
  func unmappedCodesAreNil(code: Int) {
    #expect(RequestError(from: Self.urlError(code: code), path: .satisfied) == nil)
  }

  @Test
  func foreignDomainsAreNil() {
    #expect(
      RequestError(from: NSError(domain: "com.example", code: -1004), path: .satisfied) == nil)
  }

  // MARK: - normalizingTransportFailure

  @Test
  func normalizingConvertsConnectivityFailures() {
    let result = RequestError.normalizingTransportFailure(
      URLError(.notConnectedToInternet), path: .satisfied)
    guard case .connectivity(.notConnectedToInternet, .offline, _) = result as? RequestError else {
      Issue.record("Expected .connectivity(notConnectedToInternet, offline), got \(result)")
      return
    }
  }

  // Cancellation, SSL and the non-reachability codes reach callers exactly as
  // before: callers check cancellation by domain/code, and nothing about those
  // failures changed.
  @Test(arguments: [
    URLError.Code.cancelled, .serverCertificateUntrusted, .badServerResponse, .badURL,
  ])
  func normalizingPassesOtherURLErrorsThrough(code: URLError.Code) {
    let result = RequestError.normalizingTransportFailure(URLError(code), path: .unsatisfied)
    #expect(result is URLError)
    #expect((result as? URLError)?.code == code)
  }

  @Test
  func normalizingPassesUnrelatedErrorsThrough() {
    struct Custom: Error, Equatable {}
    #expect(
      RequestError.normalizingTransportFailure(Custom(), path: .unsatisfied) as? Custom == Custom())
  }

  // Code that only knows `localizedDescription` keeps reading the system message.
  @Test
  func localizedDescriptionIsTheSystemMessage() {
    let error: any Error = RequestError.connectivity(
      code: .cannotConnectToHost, kind: .serverNotResponding,
      detail: "Could not connect to the server.")
    #expect(error.localizedDescription == "Could not connect to the server.")
  }
}
