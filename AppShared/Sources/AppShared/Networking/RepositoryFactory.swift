//
//  RepositoryFactory.swift
//  AppShared
//
//  The single place that assembles the per-server repository stack
//  `CachingRepository(NeedsAuthRepository(ApiRepository))`. Both the app shell
//  (for the active, displayed connection) and the multi-server `SyncEngine` (for
//  every inactive connection) build through here, so the layering — cache
//  outermost, 401 → needs-auth interception underneath — is byte-identical for
//  every server.
//

import Common
import Foundation
import Networking
import Persistence

/// Build the caching repository stack for a stored connection.
///
/// The connection's token may be `nil` (a config-synced-but-uncredentialed
/// server whose credential hasn't arrived yet); the stack still builds, and the
/// first authenticated call 401s into per-server needs-auth via
/// ``NeedsAuthRepository``. Callers that want to avoid the doomed round-trip
/// should short-circuit on a missing token *before* calling this.
///
/// `contentStore` and `fileIndex` are where downloaded files are kept and
/// recorded; without them nothing is cached.
@MainActor
public func makeCachingRepository(
  for stored: StoredConnection,
  database: Database,
  mode: ApiRepository.Mode = Bundle.main.appConfiguration.mode,
  contentStore: ContentStore? = nil,
  fileIndex: (any FileIndex)? = nil
) async throws -> CachingRepository<NeedsAuthRepository<ApiRepository>> {
  let connection = try stored.connection
  let api = await ApiRepository(
    connection: connection, mode: mode, contentStore: contentStore, fileIndex: fileIndex)
  let needsAuth = NeedsAuthRepository(
    wrapping: api, serverID: stored.id, database: database)
  // Caching outermost: reads come from the GRDB cache, while sync's network
  // calls still flow through the needs-auth 401 interception.
  return CachingRepository(wrapping: needsAuth, database: database, serverID: stored.id)
}
