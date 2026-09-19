//
//  SyncFailureTest.swift
//  Networking
//
//  The sync-failure rule: which failures are routine and which are
//  degradations, what level each logs at, and how a server's failure ledger
//  records and clears them.
//

import Common
import Foundation
import Testing
import os

@testable import Networking

@Suite struct SyncFailureTest {
  private struct SomeDatabaseError: Error {}

  private static func connectivity(_ kind: TransportFailureKind) -> RequestError {
    .connectivity(
      code: .cannotConnectToHost, kind: kind, detail: "Could not connect to the server.")
  }

  private static let serverError = RequestError.unexpectedStatusCode(
    code: .internalServerError, detail: "boom")

  // MARK: - Classification

  @Test(
    "Cancellation, permission and offline failures are routine",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func routineFailures() {
    #expect(SyncFailureClass(CancellationError()) == .cancelled)
    #expect(SyncFailureClass(URLError(.cancelled)) == .cancelled)
    #expect(SyncFailureClass(RequestError.forbidden(detail: nil)) == .routine)
    #expect(SyncFailureClass(RequestError.unauthorized(detail: "")) == .routine)
    #expect(SyncFailureClass(ResourceForbidden(Int.self, response: nil)) == .routine)
    #expect(SyncFailureClass(Self.connectivity(.offline)) == .offline)
    #expect(SyncFailureClass(URLError(.notConnectedToInternet)) == .offline)

    for error: any Error in [
      CancellationError(), RequestError.forbidden(detail: nil), Self.connectivity(.offline),
    ] {
      #expect(!SyncFailureClass(error).isSurfaced)
    }
  }

  @Test(
    "A server that doesn't answer is unreachable, not offline",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663),
    arguments: [TransportFailureKind.hostNotFound, .serverNotResponding, .connectionLost])
  func unreachable(kind: TransportFailureKind) {
    let failureClass = SyncFailureClass(Self.connectivity(kind))
    #expect(failureClass == .unreachable)
    #expect(failureClass.isSurfaced)
  }

  @Test(
    "A raw URL error is classified by its code alone",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func rawURLError() {
    #expect(SyncFailureClass(URLError(.timedOut)) == .unreachable)
    #expect(SyncFailureClass(URLError(.cannotFindHost)) == .unreachable)
    // Not connectivity-class: the server answered, just not usefully.
    #expect(SyncFailureClass(URLError(.badServerResponse)) == .degraded)
  }

  @Test(
    "Server errors, TLS, version and local failures are degradations",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func degradations() {
    for error: any Error in [
      Self.serverError,
      RequestError.certificate(detail: "bad cert"),
      RequestError.unsupportedVersion(sentVersion: 9),
      RequestError.invalidResponse,
      RequestError.other("decode"),
      SomeDatabaseError(),
    ] {
      let failureClass = SyncFailureClass(error)
      #expect(failureClass == .degraded)
      #expect(failureClass.isSurfaced)
    }
  }

  // MARK: - Log levels

  @Test(
    "Nothing routine logs above info; degradations log at error",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func logLevels() {
    #expect(SyncFailureClass.cancelled.logLevel() == .debug)
    #expect(SyncFailureClass.routine.logLevel() == .info)
    // However often it happens: being offline is not an error.
    #expect(SyncFailureClass.offline.logLevel(consecutiveFailures: 50) == .info)
    #expect(SyncFailureClass.degraded.logLevel() == .error)
  }

  @Test(
    "An unreachable server escalates to error only once it repeats",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func unreachableEscalates() {
    let threshold = SyncFailureClass.unreachableEscalation
    for count in 1..<threshold {
      #expect(SyncFailureClass.unreachable.logLevel(consecutiveFailures: count) == .default)
    }
    #expect(SyncFailureClass.unreachable.logLevel(consecutiveFailures: threshold) == .error)
  }

  @Test(
    "A read answered from the cache stays quiet unless the server misbehaved",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func readFallbackLevels() {
    #expect(SyncFailureClass.offline.readFallbackLogLevel == .info)
    #expect(SyncFailureClass.unreachable.readFallbackLogLevel == .info)
    #expect(SyncFailureClass.degraded.readFallbackLogLevel == .default)
  }

  // MARK: - Ledger

  @Test(
    "A surfaced failure is recorded, counted, and cleared by the next success",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func ledgerRecordsAndClears() {
    var ledger = SyncFailureLedger()
    let t0 = Date(timeIntervalSince1970: 1000)
    let t1 = Date(timeIntervalSince1970: 2000)

    let first = ledger.recordFailure(Self.serverError, at: .uiSettings, message: "boom", now: t0)
    #expect(first.failureClass == .degraded)
    #expect(first.logLevel == .error)
    #expect(first.consecutiveFailures == 1)

    let second = ledger.recordFailure(
      Self.serverError, at: .uiSettings, message: "boom again", now: t1)
    #expect(second.consecutiveFailures == 2)
    #expect(
      ledger[.uiSettings]
        == SyncFailureLedger.Entry(
          site: .uiSettings, failureClass: .degraded, message: "boom again", failedAt: t1,
          consecutiveFailures: 2))

    let cleared = ledger.recordSuccess(at: .uiSettings)
    #expect(cleared)
    #expect(ledger.isEmpty)
    // Nothing left to clear.
    let clearedAgain = ledger.recordSuccess(at: .uiSettings)
    #expect(!clearedAgain)
  }

  @Test(
    "Offline, permission and cancelled failures neither add nor clear an entry",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func ledgerIgnoresRoutine() {
    var ledger = SyncFailureLedger()
    for error: any Error in [
      Self.connectivity(.offline), RequestError.forbidden(detail: nil), CancellationError(),
    ] {
      let outcome = ledger.recordFailure(error, at: .elements, message: "unused")
      #expect(outcome.consecutiveFailures == 0)
      #expect([OSLogType.debug, .info].contains(outcome.logLevel))
    }
    #expect(ledger.isEmpty)

    // A real failure recorded before the network went away survives it: the
    // offline attempt says nothing about whether the server is fixed.
    ledger.recordFailure(Self.serverError, at: .elements, message: "boom")
    ledger.recordFailure(Self.connectivity(.offline), at: .elements, message: "offline")
    #expect(ledger[.elements]?.message == "boom")
    #expect(ledger[.elements]?.consecutiveFailures == 1)
  }

  @Test(
    "Sites are independent, and listed in a fixed order",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func ledgerSitesIndependent() {
    var ledger = SyncFailureLedger()
    ledger.recordFailure(Self.serverError, at: .detailFill, message: "a")
    ledger.recordFailure(Self.connectivity(.serverNotResponding), at: .deletions, message: "b")
    ledger.recordFailure(Self.serverError, at: .uiSettings, message: "c")
    #expect(ledger.current.map(\.site) == [.uiSettings, .deletions, .detailFill])

    ledger.recordSuccess(at: .deletions)
    #expect(ledger.current.map(\.site) == [.uiSettings, .detailFill])

    ledger.reset()
    #expect(ledger.isEmpty)
  }

  // MARK: - Absorbed failures

  @Test(
    "A phase reports the first absorbed failure worth surfacing",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func firstSurfacedKeepsTheFirstRealFailure() {
    var held: (any Error)?

    // The failures before the first surfaced one leave nothing behind.
    held = SyncFailureClass.firstSurfaced(held, CancellationError())
    #expect(held == nil)
    held = SyncFailureClass.firstSurfaced(held, RequestError.forbidden(detail: nil))
    #expect(held == nil)

    held = SyncFailureClass.firstSurfaced(held, Self.serverError)
    #expect(held as? RequestError == Self.serverError)

    // And a later one — of any class — does not displace it.
    held = SyncFailureClass.firstSurfaced(held, Self.connectivity(.hostNotFound))
    held = SyncFailureClass.firstSurfaced(held, Self.connectivity(.offline))
    #expect(held as? RequestError == Self.serverError)
  }

  @Test(
    "A pass that only ever went offline has nothing to report",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func firstSurfacedIgnoresOffline() {
    var held: (any Error)?
    for error: any Error in [
      Self.connectivity(.offline), URLError(.notConnectedToInternet),
      RequestError.unauthorized(detail: ""), CancellationError(),
    ] {
      held = SyncFailureClass.firstSurfaced(held, error)
    }
    #expect(held == nil)

    // Recording that non-result leaves the ledger — and so the Offline & Sync
    // screen — exactly as it was.
    var ledger = SyncFailureLedger()
    if let held { ledger.recordFailure(held, at: .detailFill, message: "x") }
    #expect(ledger.isEmpty)
  }

  @Test(
    "An unreachable server absorbed mid-pass is still worth reporting",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func firstSurfacedKeepsUnreachable() {
    let held = SyncFailureClass.firstSurfaced(nil, Self.connectivity(.serverNotResponding))
    #expect(held != nil)
    #expect(SyncFailureClass(held!) == .unreachable)
  }

  @Test(
    "An unreachable site escalates its log level across consecutive failures",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/663", id: 663))
  func ledgerEscalates() {
    var ledger = SyncFailureLedger()
    let error = Self.connectivity(.hostNotFound)
    var levels: [OSLogType] = []
    for _ in 0..<SyncFailureClass.unreachableEscalation {
      levels.append(ledger.recordFailure(error, at: .elements, message: "x").logLevel)
    }
    #expect(levels.last == .error)
    #expect(levels.dropLast().allSatisfy { $0 == .default })

    // A success resets the run.
    ledger.recordSuccess(at: .elements)
    let afterRecovery = ledger.recordFailure(error, at: .elements, message: "x")
    #expect(afterRecovery.logLevel == .default)
  }
}
