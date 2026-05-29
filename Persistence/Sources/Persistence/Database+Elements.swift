import DataModel
import Foundation
import GRDB
import os

/// Element-cache operations. Like `Database+Connections`, these are the only
/// entry points AppShared uses to read or mutate element rows; GRDB stays
/// sealed inside `Persistence`.
///
/// Reads are pure cache reads (no network — that's the caching repository's
/// `sync`). Writes are either a full per-server reconcile (`replaceElements`,
/// used by sync, which also handles server-side deletes) or a single
/// write-through (`upsertElement` / `deleteElement`, used by pessimistic
/// mutations).
extension Database {
  // MARK: - Multi-row collections

  /// All cached rows of one element kind for a server, ordered by name.
  public func elements<R: ElementRecord>(
    _ type: R.Type, serverID: UUID
  ) throws -> [R.Domain] {
    try writer.read { db in
      try R
        .filter(Column("server_id") == serverID)
        .order(Column("name"))
        .fetchAll(db)
        .map(\.domain)
    }
  }

  /// A single cached element by `(server, id)`, or `nil` if not cached.
  public func element<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt
  ) throws -> R.Domain? {
    try writer.read { db in
      try R
        .filter(Column("server_id") == serverID && Column("id") == id)
        .fetchOne(db)?
        .domain
    }
  }

  /// Replace the entire cached set for a server in one transaction: delete the
  /// existing rows, insert the new ones. This is how `sync` propagates
  /// server-side deletions (rows absent from `domains` disappear).
  public func replaceElements<R: ElementRecord>(
    _ domains: [R.Domain], of type: R.Type, serverID: UUID
  ) throws {
    try writer.write { db in
      try R.filter(Column("server_id") == serverID).deleteAll(db)
      for domain in domains {
        try R(serverId: serverID, domain: domain).insert(db)
      }
    }
  }

  /// Insert or replace a single cached row (pessimistic mutation write-through).
  public func upsertElement<R: ElementRecord>(
    _ domain: R.Domain, of type: R.Type, serverID: UUID
  ) throws {
    try writer.write { db in
      try R(serverId: serverID, domain: domain).upsert(db)
    }
  }

  /// Delete a single cached row by `(server, id)` (pessimistic delete).
  public func deleteElement<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt
  ) throws {
    try writer.write { db in
      _ =
        try R
        .filter(Column("server_id") == serverID && Column("id") == id)
        .deleteAll(db)
    }
  }

  // MARK: - Singletons

  public func uiSettings(serverID: UUID) throws -> UISettings? {
    try writer.read { db in
      try UISettingsRecord.fetchOne(db, key: serverID)?.domain
    }
  }

  public func setUISettings(_ value: UISettings, serverID: UUID) throws {
    try writer.write { db in
      try UISettingsRecord(serverId: serverID, domain: value).upsert(db)
    }
  }

  public func serverConfiguration(serverID: UUID) throws -> ServerConfiguration? {
    try writer.read { db in
      try ServerConfigurationRecord.fetchOne(db, key: serverID)?.domain
    }
  }

  public func setServerConfiguration(_ value: ServerConfiguration, serverID: UUID) throws {
    try writer.write { db in
      try ServerConfigurationRecord(serverId: serverID, domain: value).upsert(db)
    }
  }

  // MARK: - Observation

  /// A signal stream that fires whenever any element table is written in this
  /// process. Backed by GRDB `DatabaseRegionObservation` (transaction-level,
  /// no value coalescing), so every in-process write — sync, write-through,
  /// or a background task — is captured.
  ///
  /// Stage 7 emits the full `ElementKind` set per change; the store hydrates
  /// each kind (a cheap cache read). No initial value is emitted on subscribe:
  /// the store performs an explicit initial hydrate.
  public func observeElements() -> AsyncStream<CacheChange> {
    let regions: [any DatabaseRegionConvertible] = [
      TagRecord.all(),
      CorrespondentRecord.all(),
      DocumentTypeRecord.all(),
      StoragePathRecord.all(),
      SavedViewRecord.all(),
      UserRecord.all(),
      UserGroupRecord.all(),
      CustomFieldRecord.all(),
      UISettingsRecord.all(),
      ServerConfigurationRecord.all(),
    ]
    let observation = DatabaseRegionObservation(tracking: regions)
    let writer = writer
    return AsyncStream { continuation in
      let cancellable = observation.start(in: writer) { error in
        Logger.persistence.error("Element observation failed: \(error)")
        continuation.finish()
      } onChange: { _ in
        continuation.yield(.elements(kinds: Set(ElementKind.allCases)))
      }
      continuation.onTermination = { _ in cancellable.cancel() }
    }
  }
}
