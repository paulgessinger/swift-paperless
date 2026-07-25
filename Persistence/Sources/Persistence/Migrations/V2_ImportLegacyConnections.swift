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
      let record = ConnectionRecord(legacy: legacy, fallbackId: uuid)
      try record.insert(db)
    }
    Logger.persistence.info(
      "Imported \(decoded.count, privacy: .public) connection(s) from UserDefaults")
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

extension ConnectionRecord {
  /// Build a `ConnectionRecord` from a decoded legacy JSON row.
  ///
  /// - Parameter fallbackId: id pulled from the surrounding dict key, used
  ///   only if the row itself lacks one (older payloads may omit it).
  init(legacy: LegacyStoredConnection, fallbackId: UUID) {
    self.init(
      id: legacy.id ?? fallbackId,
      url: legacy.url,
      friendlyName: legacy.friendlyName,
      identity: legacy.identity,
      user: .init(
        id: legacy.user.id,
        isSuperUser: legacy.user.is_superuser,
        username: legacy.user.username,
        groups: legacy.user.groups ?? []),
      extraHeaders: (legacy.extraHeaders ?? []).map { header in
        .init(
          id: header.id ?? UUID(),
          key: header.key,
          value: header.value)
      },
      needsAuth: false)
  }
}
