//
//  ScanErrorMappingTest.swift
//  Scanning
//

import Foundation
import SwiftESCL
import Testing

@testable import Scanning

@Suite
struct ScanErrorMappingTest {
  @Test func reportsABusyScannerAsBusy() {
    #expect(
      ScannerClient.mapped(ScannerRepresentationError.serviceUnavailable) as? ScanError == .busy)
    #expect(ScannerClient.mapped(ScanJobError.scannerNotReady(.processing)) as? ScanError == .busy)
    #expect(ScannerClient.mapped(ScanJobError.deviceUnavailable) as? ScanError == .busy)
  }

  @Test func reportsAnAbsentScannerAsUnreachable() {
    #expect(
      ScannerClient.mapped(ScannerRepresentationError.notFound) as? ScanError == .unreachable)
    #expect(
      ScannerClient.mapped(URLError(.cannotConnectToHost)) as? ScanError == .unreachable)
  }

  /// A cancelled `URLSession` request is what a stopped scan actually throws.
  /// Mapping it to `.unreachable` would put "the scanner did not respond" on
  /// screen after the user pressed Cancel.
  @Test func treatsACancelledRequestAsCancellation() {
    #expect(ScannerClient.mapped(URLError(.cancelled)) is CancellationError)
    #expect(ScannerClient.mapped(CancellationError()) is CancellationError)
    #expect(ScannerClient.mapped(ScanJobError.cancelled) is CancellationError)
  }

  @Test func keepsTimeoutsDistinctFromAnUnreachableScanner() {
    #expect(ScannerClient.mapped(URLError(.timedOut)) as? ScanError == .timedOut)
    #expect(ScannerClient.mapped(ScanError.timedOut) as? ScanError == .timedOut)
  }

  @Test func passesOurOwnErrorsThrough() {
    #expect(ScannerClient.mapped(ScanError.noPages) as? ScanError == .noPages)
  }

  @Test func surfacesWhatTheScannerReported() {
    #expect(
      ScannerClient.mapped(ScannerRepresentationError.unexpectedStatus(409, nil)) as? ScanError
        == .scannerReported("HTTP 409"))
  }
}
