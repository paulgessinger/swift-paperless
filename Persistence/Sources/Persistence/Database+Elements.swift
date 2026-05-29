import DataModel
import Foundation
import GRDB

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
}
