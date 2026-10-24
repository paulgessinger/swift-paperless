import Foundation
import GRDB

/// A saved view kept on the device, and the `QueryKey` its membership is
/// stored under.
public struct KeptOfflineView: Sendable, Equatable {
  public var savedViewID: UInt
  public var queryKey: QueryKey
  public var keptAt: Date
}

/// The saved views kept offline. A kept view keeps every document it lists in
/// `query_order`, through the same rule as a document kept on its own
/// (`keptOfflineExists`). Async only, like every table but `server`.
extension Database {
  /// Keep a saved view whose membership is stored under `queryKey`. Keeping
  /// again refreshes the key and `kept_at`.
  public func keepOfflineView(
    serverID: UUID, savedViewID: UInt, queryKey: QueryKey, at date: Date = Date()
  ) async throws {
    try await wrappingAsync("keepOfflineView") {
      try await writer.write { db in
        try KeptOfflineViewRecord(
          serverId: serverID, savedViewId: savedViewID, queryKey: queryKey.rawValue,
          keptAt: date.timeIntervalSinceReferenceDate
        ).save(db)
      }
    }
  }

  /// Stop keeping a saved view. Its documents stay protected while something
  /// else keeps them.
  public func releaseOfflineView(serverID: UUID, savedViewID: UInt) async throws {
    try await wrappingAsync("releaseOfflineView") {
      try await writer.write { db in
        _ = try Self.keptView(serverID: serverID, savedViewID: savedViewID).deleteAll(db)
      }
    }
  }

  /// The kept views of a server, most recently kept first.
  public func keptOfflineViews(serverID: UUID) async throws -> [KeptOfflineView] {
    try await wrappingAsync("keptOfflineViews") {
      try await writer.read { db in
        try KeptOfflineViewRecord
          .filter(Column("server_id") == serverID)
          .order(Column("kept_at").desc, Column("saved_view_id").desc)
          .fetchAll(db)
          .map {
            KeptOfflineView(
              savedViewID: $0.savedViewId, queryKey: QueryKey(stored: $0.queryKey),
              keptAt: Date(timeIntervalSinceReferenceDate: $0.keptAt))
          }
      }
    }
  }

  /// Live set of kept saved-view ids, for the view's toggle and badge.
  public func observeKeptOfflineViewIDs(serverID: UUID) -> AsyncThrowingStream<Set<UInt>, Error> {
    let observation =
      ValueObservation
      .tracking { db in
        try KeptOfflineViewRecord
          .filter(Column("server_id") == serverID)
          .select(Column("saved_view_id"), as: UInt.self)
          .fetchSet(db)
      }
      .removeDuplicates()
    return stream(observation)
  }

  /// Bring the kept views in line with the server's saved views: `currentKeys`
  /// maps every saved view the server returned to its key. A kept view missing
  /// from it was deleted and is released; one whose key moved (its filter or
  /// sort was edited) follows it. Only call with the server's complete list.
  ///
  /// - Returns: the released saved-view ids.
  @discardableResult
  public func reconcileKeptOfflineViews(
    serverID: UUID, currentKeys: [UInt: QueryKey]
  ) async throws -> Set<UInt> {
    try await wrappingAsync("reconcileKeptOfflineViews") {
      try await writer.write { db in
        var released: Set<UInt> = []
        let kept = try KeptOfflineViewRecord.filter(Column("server_id") == serverID).fetchAll(db)
        for var record in kept {
          guard let key = currentKeys[record.savedViewId] else {
            try record.delete(db)
            released.insert(record.savedViewId)
            continue
          }
          if record.queryKey != key.rawValue {
            record.queryKey = key.rawValue
            try record.update(db)
          }
        }
        return released
      }
    }
  }

  private static func keptView(serverID: UUID, savedViewID: UInt)
    -> QueryInterfaceRequest<KeptOfflineViewRecord>
  {
    KeptOfflineViewRecord.filter(
      Column("server_id") == serverID && Column("saved_view_id") == savedViewID)
  }
}
