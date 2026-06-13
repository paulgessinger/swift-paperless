//
//  ConnectionMapping.swift
//  AppShared
//
//  Bridges Networking's `StoredConnection` / `Connection.HeaderValue` /
//  `DataModel.User` to / from `Persistence.ConnectionRecord`. Lives in
//  AppShared because Persistence is forbidden from depending on Networking
//  (the Wire ↔ Domain ↔ Record rule), and AppShared is the only layer that
//  already imports both.
//

import DataModel
import Foundation
import Networking
import Persistence

extension StoredConnection {
  /// Build a `StoredConnection` from a fetched GRDB record.
  public init(record: ConnectionRecord) {
    self.init(
      id: record.id,
      url: record.url,
      extraHeaders: record.extraHeaders.map { header in
        var value = Connection.HeaderValue(key: header.key, value: header.value)
        value.id = header.id
        return value
      },
      user: User(
        id: record.user.id,
        isSuperUser: record.user.isSuperUser,
        username: record.user.username,
        groups: record.user.groups),
      identity: record.identity,
      friendlyName: record.friendlyName,
      offlineBrowsingMode: OfflineBrowsingMode(rawValue: record.offlineBrowsingMode)
        ?? .recentlyBrowsed)
  }

  /// Project a `StoredConnection` into a record for write-through to GRDB.
  ///
  /// - Parameter needsAuth: caller supplies the per-connection auth-needed
  ///   state (held in `ConnectionManager.needsAuthIds`). The record is the
  ///   source of truth on disk; the manager's in-memory `Set<UUID>` is just
  ///   a hydrated projection.
  public func toRecord(needsAuth: Bool) -> ConnectionRecord {
    ConnectionRecord(
      id: id,
      url: url,
      friendlyName: friendlyName,
      identity: identity,
      user: ConnectionRecord.StoredUser(
        id: user.id,
        isSuperUser: user.isSuperUser,
        username: user.username,
        groups: user.groups),
      extraHeaders: extraHeaders.map { header in
        ConnectionRecord.StoredHeader(
          id: header.id, key: header.key, value: header.value)
      },
      needsAuth: needsAuth,
      offlineBrowsingMode: offlineBrowsingMode.rawValue)
  }
}
