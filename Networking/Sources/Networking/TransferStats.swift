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
//  Scope: this records JSON/list responses that flow through `fetchData`
//  (metadata, list pages, element collections, detail, notes). File downloads
//  (streamed) and thumbnails (Nuke) take other paths and are intentionally not
//  counted here — they are explicit, user-driven transfers, not background fills.
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

  /// Record `bytes` received under the current ``category``. Cheap no-op until a
  /// sink is registered.
  public static func record(bytes: Int) {
    guard bytes > 0, let sink else { return }
    sink(bytes, category)
  }
}
