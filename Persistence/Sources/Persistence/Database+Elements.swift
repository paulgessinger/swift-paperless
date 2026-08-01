import DataModel
import Foundation
import GRDB

/// Element-cache operations. Like `Database+Connections`, these are the only
/// entry points AppShared uses to read or mutate element rows; GRDB stays
/// sealed inside `Persistence`. Every access goes through ``Database/wrapping``
/// so a GRDB failure reaches callers as a ``DatabaseError``.
///
/// Reads are pure cache reads (no network — that's the caching repository's
/// `sync`). Writes are either a full per-server reconcile (`replaceElements`,
/// used by sync, which also handles server-side deletes) or a single
/// write-through (`upsertElement` / `deleteElement`, used by pessimistic
/// mutations).
///
/// Reads go through `writer` because `DatabaseWriter` refines `DatabaseReader`;
/// on the production `DatabasePool` a `read` takes a reader connection and runs
/// concurrently with writes under WAL.
///
/// **Evolving a record's `Payload`.** The payload is JSON in the `data` column,
/// so the schema does not constrain its shape: optional fields can be added and
/// fields can be dropped freely. Adding a *required* field cannot be done in
/// place — old rows fail to decode, and because a read maps the whole
/// collection, one undecodable row fails every row of that kind. These tables
/// hold nothing but derived data, so the cheap correct move is a migration that
/// deletes the affected rows and lets the next sync refill them, rather than
/// rewriting stored JSON.
extension Database {
  // MARK: - Multi-row collections

  /// All cached rows of one element kind for a server, ordered by name.
  public func elements<R: ElementRecord>(
    _ type: R.Type, serverID: UUID
  ) throws(DatabaseError) -> [R.Domain] {
    try wrapping("elements(\(R.databaseTableName))") {
      try writer.read { db in
        try R
          .filter(Column("server_id") == serverID)
          .order(Column("name"))
          .fetchAll(db)
          .map(\.domain)
      }
    }
  }

  /// A single cached element by `(server, id)`, or `nil` if not cached.
  public func element<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt
  ) throws(DatabaseError) -> R.Domain? {
    try wrapping("element(\(R.databaseTableName))") {
      try writer.read { db in
        try R
          .filter(Column("server_id") == serverID && Column("id") == id)
          .fetchOne(db)?
          .domain
      }
    }
  }

  /// Replace the entire cached set for a server in one transaction: delete the
  /// existing rows, insert the new ones. This is how `sync` propagates
  /// server-side deletions (rows absent from `domains` disappear).
  ///
  /// `upsert` rather than `insert`: a paginated fetch can legitimately deliver
  /// the same element twice, because deleting a row server-side mid-fetch
  /// shifts later elements back a page. The last write for an id wins, and the
  /// reconcile survives the duplicate.
  public func replaceElements<R: ElementRecord>(
    _ domains: [R.Domain], of type: R.Type, serverID: UUID
  ) throws(DatabaseError) {
    try wrapping("replaceElements(\(R.databaseTableName))") {
      try writer.write { db in
        try R.filter(Column("server_id") == serverID).deleteAll(db)
        for domain in domains {
          try R(serverId: serverID, domain: domain).upsert(db)
        }
      }
    }
  }

  /// Insert or replace a single cached row (pessimistic mutation write-through).
  public func upsertElement<R: ElementRecord>(
    _ domain: R.Domain, of type: R.Type, serverID: UUID
  ) throws(DatabaseError) {
    try wrapping("upsertElement(\(R.databaseTableName))") {
      try writer.write { db in
        try R(serverId: serverID, domain: domain).upsert(db)
      }
    }
  }

  /// Delete a single cached row by `(server, id)` (pessimistic delete).
  public func deleteElement<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt
  ) throws(DatabaseError) {
    try wrapping("deleteElement(\(R.databaseTableName))") {
      try writer.write { db in
        _ =
          try R
          .filter(Column("server_id") == serverID && Column("id") == id)
          .deleteAll(db)
      }
    }
  }

  // MARK: - Singletons

  public func uiSettings(serverID: UUID) throws(DatabaseError) -> UISettings? {
    try wrapping("uiSettings") {
      try writer.read { db in
        try UISettingsRecord.fetchOne(db, key: serverID)?.domain
      }
    }
  }

  public func setUISettings(_ value: UISettings, serverID: UUID) throws(DatabaseError) {
    try wrapping("setUISettings") {
      try writer.write { db in
        try UISettingsRecord(serverId: serverID, domain: value).upsert(db)
      }
    }
  }

  public func serverConfiguration(serverID: UUID) throws(DatabaseError) -> ServerConfiguration? {
    try wrapping("serverConfiguration") {
      try writer.read { db in
        try ServerConfigurationRecord.fetchOne(db, key: serverID)?.domain
      }
    }
  }

  public func setServerConfiguration(
    _ value: ServerConfiguration, serverID: UUID
  ) throws(DatabaseError) {
    try wrapping("setServerConfiguration") {
      try writer.write { db in
        try ServerConfigurationRecord(serverId: serverID, domain: value).upsert(db)
      }
    }
  }
}
