//
//  TransferStats.swift
//  Networking
//
//  Lightweight, best-effort accounting of bytes received over the API, fed from
//  the single `ApiRepository` response chokepoint. The app registers a `sink`
//  once at startup to forward totals into an app-level observable; the active
//  `category` is a task-local set by callers around an operation (fill / sync /
//  reconcile), so the meter can break traffic down by what produced it.
//
//  Scope: this records API requests that flow through `fetchData` (metadata,
//  list pages, element collections, detail, notes). File downloads (streamed)
//  and thumbnails (Nuke) take other paths and are intentionally not counted
//  here — they are explicit, user-driven transfers, not background fills.
//
//  Bytes come from the task's `URLSessionTaskMetrics`, so they are what actually
//  crossed the wire: compressed sizes, headers included, both directions, and
//  nothing at all for a response `URLCache` served locally. Counting the decoded
//  `Data` instead overstated a gzipped JSON list several-fold, which is the
//  opposite of useful for a meter whose job is to inform the Wi‑Fi gate.
//

import Foundation

/// Coarse classification of a recorded response, for the data-transfer meter.
public enum TransferCategory: String, Sendable, CaseIterable {
  case sync  // element collections (tags, correspondents, …)
  case fill  // list / proactive library fill (metadata + detail pages)
  case reconcile  // R2 / R3δ / membership sweeps
  case other  // everything else (on-open detail, notes, suggestions, …)
}

public enum NetworkTransfer {
  /// The classification applied to responses on the current task and its
  /// structured children. Set with `NetworkTransfer.$category.withValue(.fill)
  /// { … }` around an operation. Note: `Task.detached` does *not* inherit it, so
  /// detached work (e.g. the background page-fill) must set it itself.
  @TaskLocal public static var category: TransferCategory = .other

  /// Registered once at app startup before any request runs; read on arbitrary
  /// response threads thereafter. The single pre-use assignment races nothing in
  /// practice, hence `nonisolated(unsafe)`.
  nonisolated(unsafe) public static var sink: (@Sendable (Int, TransferCategory) -> Void)?

  /// Record `bytes` transferred under the current ``category``. Cheap no-op
  /// until a sink is registered.
  ///
  /// Only correct while still inside the task that set the task-local. Bytes
  /// that arrive on a URLSession delegate callback must capture the category at
  /// request time and use ``record(bytes:category:)`` — a delegate callback runs
  /// outside the caller's task, where the task-local reads its default.
  public static func record(bytes: Int) {
    record(bytes: bytes, category: category)
  }

  /// Record `bytes` against an explicitly captured ``TransferCategory``.
  public static func record(bytes: Int, category: TransferCategory) {
    guard bytes > 0, let sink else { return }
    sink(bytes, category)
  }
}
