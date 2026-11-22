//
//  OfflineBrowsingMode.swift
//  AppShared
//

import DataModel
import Foundation

/// How aggressively the offline cache fills a given server's documents.
///
/// Every document's metadata row is cached in both modes (the one-time seed,
/// then the delta); the mode decides the rest.
///
/// - `recentlyBrowsed`: only the lists the user actually opens are cached
///   (the on-open eager fill), and only kept documents' files download.
/// - `entireLibrary`: a proactive fill caches every saved view, the default
///   list, every document's details and every file, so the whole library
///   browses offline even if never opened.
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
  /// What a newly added connection starts at. Deliberately not size-adaptive:
  /// a proactive whole-library download is opt-in. `OfflineLibrarySize` still
  /// decides whether the Offline & Sync screen *recommends* `.entireLibrary`.
  public static let initial: OfflineBrowsingMode = .recentlyBrowsed
}
