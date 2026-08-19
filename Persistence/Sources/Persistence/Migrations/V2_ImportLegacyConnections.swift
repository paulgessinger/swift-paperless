import Common
import Foundation
import GRDB
import os

/// One-time data migration: copy `[UUID: StoredConnection]` from app-group
/// `UserDefaults` (key `"Connections"`) into the GRDB `server` table.
///
/// Registered as a regular GRDB migration so idempotency is tracked by the
/// migrator's internal `grdb_migrations` table — no separate state table
/// needed. The migration is parameterised on the `UserDefaults` to read from
/// so tests can inject an isolated suite (production callers use the
/// app-group suite by default; in-memory `Database` instances skip the
/// import by passing `nil`).
///
/// Soft-fail semantics: a missing key or a corrupt JSON payload is logged
/// but the migration still succeeds. This avoids retrying a permanently
/// broken payload on every launch — affected users can re-login. A genuine
/// DB write failure still throws and the migration stays un-applied so the
/// next launch retries.
///
/// The active-connection pointer (`"ActiveConnectionId"`) is intentionally
/// **not** moved — `ConnectionManager.activeConnectionId` continues to live
/// in app-group `UserDefaults` so the Share Extension picks up changes via
/// the usual cross-process syncing.
enum V2_ImportLegacyConnections {
  /// GRDB migration identifier. Public so external integration tests can
  /// assert on it if needed.
  public static let identifier = "v2_import_legacy_userdefaults_connections"

  /// Legacy UserDefaults key carrying
  /// `JSONEncoder().encode([UUID: StoredConnection])`.
  public static let userDefaultsKey = "Connections"

  /// Migration body. `userDefaults == nil` skips the import entirely (used
  /// by in-memory test seams and by scenarios where the import is not
  /// applicable). On a non-nil `UserDefaults`, runs the import with
  /// soft-fail semantics for missing key / corrupt JSON.
  static func run(_ db: GRDB.Database, userDefaults: UserDefaults?) throws {
    guard let userDefaults else {
      Logger.persistence.debug("Skipping legacy connection import (no UserDefaults provided)")
      return
    }
    guard let data = userDefaults.object(forKey: userDefaultsKey) as? Data else {
      Logger.persistence.info(
        "Legacy connection import: '\(userDefaultsKey, privacy: .public)' key absent")
      return
    }
    let decoded: [UUID: LegacyStoredConnection]
    do {
      decoded = try JSONDecoder().decode([UUID: LegacyStoredConnection].self, from: data)
    } catch {
      Logger.persistence.error(
        "Legacy connection import skipped: JSON failed to decode (\(error))")
      return
    }
    for (uuid, legacy) in decoded {
      let user = V1StoredUser(
        groups: legacy.user.groups ?? [],
        id: legacy.user.id,
        isSuperUser: legacy.user.is_superuser,
        username: legacy.user.username)
      let headers = (legacy.extraHeaders ?? []).map {
        V1StoredHeader(id: $0.id ?? UUID(), key: $0.key, value: $0.value)
      }
      try db.execute(
        sql: """
          INSERT INTO server
            (id, url, friendly_name, identity, user, extra_headers, needs_auth,
             offline_browsing_mode)
          VALUES (?, ?, ?, ?, ?, ?, 0, 'recentlyBrowsed')
          """,
        arguments: [
          legacy.id ?? uuid, legacy.url, legacy.friendlyName, legacy.identity,
          try Self.encode(user), try Self.encode(headers),
        ])
    }
    Logger.persistence.info(
      "Imported \(decoded.count, privacy: .public) connection(s) from UserDefaults")
  }
}

// MARK: - V1 storage shape (frozen)

extension V2_ImportLegacyConnections {
  /// V1's on-disk JSON for `server.user` and `server.extra_headers`, frozen here
  /// rather than reused from `ConnectionRecord`.
  ///
  /// GRDB puts it plainly: *"migrations should not depend on application
  /// types"* — migrations describe past states of the database, while the rest
  /// of the code targets the latest one only. `ConnectionRecord` is the current
  /// struct; this migration has to keep writing what **V1** defined, forever.
  ///
  /// This is not hypothetical: the insert used to go through `ConnectionRecord`,
  /// and adding `sync_over_cellular` in `V9` immediately broke it — the record
  /// named a column that does not exist at V2 time, so the migration threw for
  /// every user upgrading from before it. The column list is spelled out below
  /// for the same reason; `needs_auth` and `offline_browsing_mode` are written
  /// as the literals V1 declared as defaults.
  fileprivate struct V1StoredUser: Encodable {
    let groups: [UInt]
    let id: UInt
    let isSuperUser: Bool
    let username: String
  }

  fileprivate struct V1StoredHeader: Encodable {
    let id: UUID
    let key: String
    let value: String
  }

  /// Sorted keys, matching what V1 wrote (deterministic on-disk output).
  fileprivate static func encode(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }
}

// MARK: - Legacy shape

/// Mirrors the on-disk JSON shape produced by
/// `StoredConnection.encode(to:)` in pre-Stage-5 `ConnectionManager.swift`
/// (the legacy inline `StoredUser` Codable). Defined here in `Persistence`
/// rather than reused from `AppShared` so the importer has zero dependency
/// on AppShared / Networking / the active `StoredConnection` type.
///
/// `Encodable` as well as `Decodable` only so the debug export
/// (``Database/exportConnectionsToLegacyUserDefaults(_:)``) can write the
/// payload this type reads. Keeping both directions on one type is the point:
/// if the shape drifts, both sides drift together.
struct LegacyStoredConnection: Codable {
  var id: UUID?
  var url: URL
  var extraHeaders: [LegacyHeader]?
  var user: LegacyUser
  var identity: String?
  var friendlyName: String?

  struct LegacyHeader: Codable {
    var id: UUID?
    var key: String
    var value: String
  }

  struct LegacyUser: Codable {
    var id: UInt
    var is_superuser: Bool
    var username: String
    var groups: [UInt]?
  }

  /// The inverse of ``ConnectionRecord/init(legacy:fallbackId:)``.
  ///
  /// `needsAuth` has no legacy counterpart and is dropped; a re-imported
  /// connection comes back with `needs_auth = false`, which is the same thing
  /// a genuine pre-Stage-5 payload would produce.
  init(record: ConnectionRecord) {
    id = record.id
    url = record.url
    extraHeaders = record.extraHeaders.map {
      LegacyHeader(id: $0.id, key: $0.key, value: $0.value)
    }
    user = LegacyUser(
      id: record.user.id,
      is_superuser: record.user.isSuperUser,
      username: record.user.username,
      groups: record.user.groups)
    identity = record.identity
    friendlyName = record.friendlyName
  }
}

