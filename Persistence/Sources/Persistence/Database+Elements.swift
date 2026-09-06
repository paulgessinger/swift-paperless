import DataModel
import Foundation
import GRDB

/// Element-cache operations. These are the only entry points AppShared uses to
/// read or mutate element rows; GRDB stays sealed inside `Persistence`. Every
/// access goes through ``Database/wrappingAsync`` so a GRDB failure reaches
/// callers as a ``DatabaseError``.
///
/// **Async only, like every cache table.** Blocking database access is allowed
/// for the `server` table and nothing else — see the rule and its rationale in
/// `Database+Connections`. A cache-table query can wait the full 5 s
/// `busy_timeout` behind another process's writer lock, so a main-actor caller
/// must suspend on GRDB's own queues rather than park the main thread there.
/// The query body lives in a `static` taking the `GRDB.Database` handle, which
/// is also what in-package seeding reuses without needing a blocking accessor.
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
  ) async throws -> [R.Domain] {
    try await wrappingAsync("elements(\(R.databaseTableName))") {
      try await writer.read { try Self.fetchElements(R.self, serverID: serverID, $0) }
    }
  }

  static func fetchElements<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, _ db: GRDB.Database
  ) throws -> [R.Domain] {
    try R
      .filter(Column("server_id") == serverID)
      .order(Column("name"))
      .fetchAll(db)
      .map(\.domain)
  }

  /// A single cached element by `(server, id)`, or `nil` if not cached.
  public func element<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt
  ) async throws -> R.Domain? {
    try await wrappingAsync("element(\(R.databaseTableName))") {
      try await writer.read { try Self.fetchElement(R.self, serverID: serverID, id: id, $0) }
    }
  }

  private static func fetchElement<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt, _ db: GRDB.Database
  ) throws -> R.Domain? {
    try R
      .filter(Column("server_id") == serverID && Column("id") == id)
      .fetchOne(db)?
      .domain
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
  ) async throws {
    try await wrappingAsync("replaceElements(\(R.databaseTableName))") {
      try await writer.write { try Self.writeElements(domains, of: R.self, serverID: serverID, $0) }
    }
  }

  static func writeElements<R: ElementRecord>(
    _ domains: [R.Domain], of type: R.Type, serverID: UUID, _ db: GRDB.Database
  ) throws {
    try R.filter(Column("server_id") == serverID).deleteAll(db)
    for domain in domains {
      try R(serverId: serverID, domain: domain).upsert(db)
    }
  }

  /// Insert or replace a single cached row (pessimistic mutation write-through).
  public func upsertElement<R: ElementRecord>(
    _ domain: R.Domain, of type: R.Type, serverID: UUID
  ) async throws {
    try await wrappingAsync("upsertElement(\(R.databaseTableName))") {
      try await writer.write { try R(serverId: serverID, domain: domain).upsert($0) }
    }
  }

  /// Delete a single cached row by `(server, id)` (pessimistic delete).
  public func deleteElement<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt
  ) async throws {
    try await wrappingAsync("deleteElement(\(R.databaseTableName))") {
      try await writer.write { try Self.removeElement(R.self, serverID: serverID, id: id, $0) }
    }
  }

  private static func removeElement<R: ElementRecord>(
    _ type: R.Type, serverID: UUID, id: UInt, _ db: GRDB.Database
  ) throws {
    _ =
      try R
      .filter(Column("server_id") == serverID && Column("id") == id)
      .deleteAll(db)
  }

  // MARK: - Singletons

  public func uiSettings(serverID: UUID) async throws -> UISettings? {
    try await wrappingAsync("uiSettings") {
      try await writer.read { try UISettingsRecord.fetchOne($0, key: serverID)?.domain }
    }
  }

  public func setUISettings(_ value: UISettings, serverID: UUID) async throws {
    try await wrappingAsync("setUISettings") {
      try await writer.write { try Self.writeUISettings(value, serverID: serverID, $0) }
    }
  }

  static func writeUISettings(
    _ value: UISettings, serverID: UUID, _ db: GRDB.Database
  ) throws {
    try UISettingsRecord(serverId: serverID, domain: value).upsert(db)
  }

  /// Read-modify-write the `ui_settings` singleton inside **one** transaction,
  /// and report whether there was a row to transform.
  ///
  /// The alternative — read through one accessor, merge, write through another
  /// — is two transactions with a suspension between them, so an element sync
  /// writing a freshly-fetched row in the gap is overwritten by a merge built
  /// on the row as it was *before* that sync, silently reverting the user and
  /// permission matrix to a stale copy. On the main actor the two calls used to
  /// be adjacent and this could not happen; they are not adjacent any more.
  ///
  /// `transform` runs inside the write transaction and must stay pure — it is
  /// handed the current value and returns the one to store.
  @discardableResult
  public func updateUISettings(
    serverID: UUID, _ transform: @escaping @Sendable (UISettings) -> UISettings
  ) async throws -> Bool {
    try await wrappingAsync("updateUISettings") {
      try await writer.write { db in
        guard let current = try UISettingsRecord.fetchOne(db, key: serverID)?.domain else {
          return false
        }
        try Self.writeUISettings(transform(current), serverID: serverID, db)
        return true
      }
    }
  }

  public func serverConfiguration(serverID: UUID) async throws -> ServerConfiguration? {
    try await wrappingAsync("serverConfiguration") {
      try await writer.read { try ServerConfigurationRecord.fetchOne($0, key: serverID)?.domain }
    }
  }

  public func setServerConfiguration(
    _ value: ServerConfiguration, serverID: UUID
  ) async throws {
    try await wrappingAsync("setServerConfiguration") {
      try await writer.write { try Self.writeServerConfiguration(value, serverID: serverID, $0) }
    }
  }

  static func writeServerConfiguration(
    _ value: ServerConfiguration, serverID: UUID, _ db: GRDB.Database
  ) throws {
    try ServerConfigurationRecord(serverId: serverID, domain: value).upsert(db)
  }
}
