import Foundation
import GRDB

/// A saved view kept on the device.
public struct KeptOfflineView: Sendable, Equatable {
  public var savedViewID: UInt
  public var keptAt: Date
}

/// The saved views kept offline. A kept view's members are `kept_offline` rows
/// carrying its id, written by the view's sync, so every protection treats
/// them like documents kept on their own. Async only, like every table but
/// `server`.
extension Database {
  /// Keep a saved view. Its members follow with its first sync
  /// (``replaceKeptOfflineViewMembers(serverID:savedViewID:documentIDs:)``).
  /// Keeping again refreshes `kept_at`.
  public func keepOfflineView(
    serverID: UUID, savedViewID: UInt, at date: Date = Date()
  ) async throws {
    try await wrappingAsync("keepOfflineView") {
      try await writer.write { db in
        try KeptOfflineViewRecord(
          serverId: serverID, savedViewId: savedViewID,
          keptAt: date.timeIntervalSinceReferenceDate
        ).save(db)
      }
    }
  }

  /// Stop keeping a saved view, and drop the rows it kept its members by. A
  /// member kept on its own, or by another view, stays kept.
  public func releaseOfflineView(serverID: UUID, savedViewID: UInt) async throws {
    try await wrappingAsync("releaseOfflineView") {
      try await writer.write { db in
        try Self.release(db, serverID: serverID, savedViewIDs: [savedViewID])
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
              savedViewID: $0.savedViewId,
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

  /// Make `documentIDs` the members of a kept view: what the server lists for
  /// it now. A view that is no longer kept is left alone, so a sync finishing
  /// after the user stopped keeping it writes nothing.
  ///
  /// - Returns: how many members joined, whose files may need queueing.
  @discardableResult
  public func replaceKeptOfflineViewMembers(
    serverID: UUID, savedViewID: UInt, documentIDs: [UInt]
  ) async throws -> Int {
    try await wrappingAsync("replaceKeptOfflineViewMembers") {
      try await writer.write { db in
        guard
          let view =
            try KeptOfflineViewRecord
            .filter(Column("server_id") == serverID && Column("saved_view_id") == savedViewID)
            .fetchOne(db)
        else { return 0 }
        let members = KeptOfflineRecord.filter(
          Column("server_id") == serverID && Column("saved_view_id") == savedViewID)
        let current = try members.select(Column("document_id"), as: UInt.self).fetchSet(db)
        let next = Set(documentIDs)
        _ = try members.filter(!next.contains(Column("document_id"))).deleteAll(db)
        let joined = next.subtracting(current)
        for documentID in joined {
          try KeptOfflineRecord(
            serverId: serverID, documentId: documentID, savedViewId: savedViewID,
            keptAt: view.keptAt
          ).insert(db)
        }
        return joined.count
      }
    }
  }

  /// Stop keeping every kept view the server no longer has: `existing` is the
  /// id of every saved view it returned. Only call with the server's complete
  /// list.
  ///
  /// - Returns: the saved-view ids no longer kept.
  @discardableResult
  public func releaseDeletedOfflineViews(serverID: UUID, existing: Set<UInt>) async throws
    -> Set<UInt>
  {
    try await wrappingAsync("releaseDeletedOfflineViews") {
      try await writer.write { db in
        let kept =
          try KeptOfflineViewRecord
          .filter(Column("server_id") == serverID)
          .select(Column("saved_view_id"), as: UInt.self)
          .fetchSet(db)
        let deleted = kept.subtracting(existing)
        try Self.release(db, serverID: serverID, savedViewIDs: deleted)
        return deleted
      }
    }
  }

  private static func release(_ db: GRDB.Database, serverID: UUID, savedViewIDs: Set<UInt>)
    throws
  {
    guard !savedViewIDs.isEmpty else { return }
    _ =
      try KeptOfflineViewRecord
      .filter(Column("server_id") == serverID && savedViewIDs.contains(Column("saved_view_id")))
      .deleteAll(db)
    _ =
      try KeptOfflineRecord
      .filter(Column("server_id") == serverID && savedViewIDs.contains(Column("saved_view_id")))
      .deleteAll(db)
  }
}
