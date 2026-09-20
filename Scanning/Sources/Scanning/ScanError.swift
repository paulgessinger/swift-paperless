//
//  ScanError.swift
//  Scanning
//

import Foundation

/// What can go wrong between picking a scanner and holding its pages.
///
/// SwiftESCL's `ScannerRepresentationError` is a transport-level enum; this is
/// the subset a user can act on, so the UI has something to say beyond "an
/// error occurred".
public enum ScanError: Error, Equatable, Sendable {
  /// The scanner did not answer. Usually asleep, off the network, or the
  /// discovered address went stale.
  case unreachable
  /// The scanner answered, but it is busy with someone else's job.
  case busy
  /// The job completed without handing back a single page. The usual cause is
  /// an empty feeder.
  case noPages
  /// The scanner produced data we could not turn into a PDF.
  case malformedDocument
  /// The scan ran past ``ScannerClient/scanTimeout`` without finishing.
  ///
  /// This is also the backstop for a real bug in SwiftESCL 4.1.1: its 503
  /// retry counter is compared but never incremented, so a scanner stuck on
  /// 503 keeps the page loop alive indefinitely.
  case timedOut
  /// The scanner rejected the job or failed midway through it.
  case scannerReported(String)
}
