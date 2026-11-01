//
//  ScannerClient.swift
//  Scanning
//

import Foundation
import SwiftESCL
import UniformTypeIdentifiers
import os

/// Talks to one scanner.
///
/// Every entry point builds its own `EsclScanner`, uses it, and drops it before
/// returning. That is not incidental: `EsclScanner` is a non-`Sendable` class
/// whose scanning methods are `nonisolated async`, so under Swift 6 an instance
/// that lives anywhere — a stored property, an actor, `ScannerBrowser.discovered`
/// — cannot be passed to them at all (`sending 'scanner' risks causing data
/// races`). Created and consumed inside a single function body, it stays in a
/// disconnected region and the calls are legal. Everything that crosses the
/// boundary is a value.
public enum ScannerClient {
  /// How long a whole scan may take before we give up on it.
  ///
  /// Generous, because an ADF stack at 600 dpi legitimately takes minutes. It
  /// It is a backstop against a scanner that never finishes a page and never
  /// errors, not a way to police slow hardware. Hitting it cancels the scan,
  /// which releases the job on the device.
  public static let scanTimeout: Duration = .seconds(300)

  /// How many 503s in a row to tolerate before giving up on a page.
  private static let maxBusyRetries = 3

  private static func make(_ ref: ScannerRef) throws -> EsclScanner {
    try EsclScanner(
      id: ref.id,
      hostname: ref.hostname,
      port: ref.port,
      location: ref.location,
      model: ref.model,
      root: ref.root,
      esclVersion: ref.esclVersion,
      usePlainText: ref.usePlainText
    )
  }

  /// Asks the scanner what it can do.
  ///
  /// A capability document that parses to nothing comes back as
  /// ``ScannerCapabilities/isEmpty`` rather than an error; the caller decides
  /// whether to substitute ``ScannerCapabilities/fallback``.
  @concurrent
  public static func capabilities(of ref: ScannerRef) async throws -> ScannerCapabilities {
    do {
      let scanner = try make(ref)
      let raw = try await scanner.getCapabilities()
      return ScannerCapabilities(raw, esclVersionFallback: ref.esclVersion)
    } catch {
      throw mapped(error)
    }
  }

  /// Runs one scan start to finish and hands back one payload per document the
  /// scanner produced.
  ///
  /// - Parameter progress: yields the current fraction as the pages come down.
  ///   The continuation is finished before returning, whether or not the scan
  ///   succeeded.
  @concurrent
  public static func scan(
    _ ref: ScannerRef,
    _ request: ScanRequest,
    progress: AsyncStream<Double>.Continuation? = nil
  ) async throws -> [Data] {
    defer { progress?.finish() }

    // The scan and the deadline race as siblings. Whichever finishes first wins
    // and the other is cancelled — which for the scan means `performScan` gets
    // to tell the device to drop the job rather than leaving it occupied.
    //
    // A plain `Task` + watchdog would not work here: the closure would have to
    // be `@Sendable`, and nothing non-`Sendable` may be captured, so the scanner
    // has to be built *inside* the child task. That is what `run(_:_:_:)` does.
    return try await withThrowingTaskGroup(of: [Data].self) { group in
      group.addTask { try await run(ref, request, progress) }
      group.addTask {
        try await Task.sleep(for: scanTimeout)
        throw ScanError.timedOut
      }

      guard let pages = try await group.next() else {
        throw ScanError.timedOut
      }
      group.cancelAll()
      return pages
    }
  }

  /// The scan itself, with every SwiftESCL value confined to this body.
  @concurrent
  private static func run(
    _ ref: ScannerRef,
    _ request: ScanRequest,
    _ progress: AsyncStream<Double>.Continuation?
  ) async throws -> [Data] {
    do {
      let scanner = try make(ref)

      // Re-read capabilities so the colour mode lands on a value this scanner
      // named itself rather than the canonical one. It is one cheap GET against
      // a device we are about to occupy for minutes — but a capability document
      // we cannot parse is not a reason to refuse to scan.
      var supportedModes: [ColorMode] = []
      do {
        let raw = try await scanner.getCapabilities()
        supportedModes = raw.sourceCapabilities[request.source.esclSource]?.colorModes ?? []
      } catch {
        Logger.scanning.warning(
          "Could not read capabilities before scanning: \(String(describing: error))")
      }

      let settings = request.esclSettings(
        version: ref.esclVersion ?? "2.0", supportedModes: supportedModes)

      // The page loop is ours rather than `performScan`'s, because the job has
      // to be released on every exit and `performScan` cannot do that: its only
      // cancellation check sits at the top of its loop, so a cancellation that
      // lands while it is awaiting a page throws straight past it. Its retry
      // counter is also compared but never incremented, so a scanner answering
      // 503 keeps it alive indefinitely.
      let jobId = try await scanner.startJob(settings)
      Logger.scanning.info("Started scan job")

      do {
        var pages: [Data] = []
        var retries = 0

        while true {
          try Task.checkCancellation()

          do {
            // The library hands the closure a non-`Sendable` `Progress`; only
            // the fraction escapes it. Yielding into the stream keeps the
            // updates ordered, which a `Task { @MainActor in ... }` per
            // callback would not.
            pages.append(
              try await scanner.getNextDocument(for: jobId) { report, _ in
                progress?.yield(report.fractionCompleted)
              })
            retries = 0
          } catch ScannerRepresentationError.notFound {
            // eSCL signals "no more documents" with a 404 on NextDocument.
            break
          } catch ScannerRepresentationError.serviceUnavailable
            where retries < maxBusyRetries
          {
            // Some scanners answer 503 between the pages of one job.
            retries += 1
            try await Task.sleep(for: .seconds(1))
          }
        }

        guard !pages.isEmpty else {
          Logger.scanning.warning("Scan job completed but returned no documents")
          throw ScanError.noPages
        }

        Logger.scanning.info("Scan returned \(pages.count) document(s)")
        return pages
      } catch {
        // Cancelled, timed out, or the transport failed: the scanner is still
        // holding the job, and will keep feeding paper and refuse the next one
        // until its own timeout expires. Hand it back.
        await release(jobId, of: ref)
        throw error
      }
    } catch {
      throw mapped(error)
    }
  }

  /// Tells the scanner to drop a job we are not going to finish.
  ///
  /// Detached on purpose: this runs *because* the surrounding task was
  /// cancelled, and an inherited cancellation would abort the request before it
  /// reached the device. It builds its own scanner for the same reason ``run``
  /// does — an `EsclScanner` cannot cross into another task.
  ///
  /// `EsclScanner.cancelJob` is deliberately not used. It GETs the job URI,
  /// which reads the job; eSCL cancels one with `DELETE`.
  private static func release(_ jobId: String, of ref: ScannerRef) async {
    await Task.detached {
      do {
        try await make(ref)
          .sendRequestAndIgnoreResponse(method: "DELETE", endPoint: .scanJob(jobId))
        Logger.scanning.info("Released the scan job")
      } catch {
        Logger.scanning.warning("Could not release the scan job: \(String(describing: error))")
      }
    }.value
  }

  static func mapped(_ error: any Error) -> any Error {
    if let error = error as? ScanError { return error }

    switch error {
    case ScannerRepresentationError.serviceUnavailable:
      return ScanError.busy
    case ScannerRepresentationError.notFound, ScannerRepresentationError.invalidUrl:
      return ScanError.unreachable
    case ScannerRepresentationError.invalidResponse:
      return ScanError.malformedDocument
    case ScannerRepresentationError.unexpectedStatus(let code, _):
      return ScanError.scannerReported("HTTP \(code)")
    case ScannerRepresentationError.unexpectedScanJobState(let state):
      return ScanError.scannerReported(state.rawValue)
    case ScanJobError.cancelled:
      return CancellationError()
    case ScanJobError.scannerNotReady, ScanJobError.deviceUnavailable:
      return ScanError.busy
    case ScanJobError.conflictingArguments:
      return ScanError.scannerReported("conflicting scan settings")
    case ScanJobError.noJobIdReceived:
      return ScanError.malformedDocument
    case is CancellationError:
      return error
    case let error as URLError where error.code == .cancelled:
      // What a cancelled URLSession request throws. Reporting it as a dead
      // scanner would put an error alert on top of a scan the user stopped.
      return CancellationError()
    case let error as URLError where error.code == .timedOut:
      return ScanError.timedOut
    case is URLError:
      return ScanError.unreachable
    default:
      Logger.scanning.error("Unmapped scanner error: \(String(describing: error))")
      return error
    }
  }
}
