//
//  OfflineBrowsingMode.swift
//  AppShared
//

import DataModel
import Foundation

/// How aggressively the offline cache fills a given server's documents.
///
/// - `recentlyBrowsed`: only queries the user actually opens are cached
///   (Stage 8 on-open fill).
/// - `entireLibrary`: a proactive fill caches every saved view and the default
///   list, so the whole library browses offline even if never opened.
///
/// **Per-server**: persisted on each server's connection record
/// (`ConnectionRecord.offlineBrowsingMode`) — a large work server can stay
/// *recently browsed* while a personal server goes *entire library*. As durable
/// user config it survives a cache wipe (unlike the regenerable per-server sync
/// cursors, which live in `server_sync_state`).
public enum OfflineBrowsingMode: String, Codable, CaseIterable, Sendable {
  case recentlyBrowsed
  case entireLibrary
}

extension OfflineBrowsingMode {
  /// Size-adaptive default for a newly added connection. The comparison
  /// itself is `DataModel.OfflineLibrarySize.isSmall(documentCount:)` — kept
  /// there so it's unit-testable; this is a thin, effectively untested
  /// adapter (one branch, no logic of its own).
  public static func `default`(forDocumentCount count: UInt?) -> OfflineBrowsingMode {
    OfflineLibrarySize.isSmall(documentCount: count) ? .entireLibrary : .recentlyBrowsed
  }
}
