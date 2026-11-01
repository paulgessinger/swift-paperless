import Foundation
import GRDB

/// The tags preselected when uploading to a server. Async only, like every
/// table but `server`.
extension Database {
  /// A server's default upload tags, by tag id.
  public func defaultUploadTags(serverID: UUID) async throws -> [UInt] {
    try await wrappingAsync("defaultUploadTags") {
      try await writer.read { db in
        try DefaultUploadTagRecord
          .filter(Column("server_id") == serverID)
          .order(Column("tag_id"))
          .fetchAll(db)
          .map(\.tagId)
      }
    }
  }

  /// Replaces a server's default upload tags.
  public func setDefaultUploadTags(_ tags: [UInt], serverID: UUID) async throws {
    try await wrappingAsync("setDefaultUploadTags") {
      try await writer.write { db in
        _ =
          try DefaultUploadTagRecord
          .filter(Column("server_id") == serverID)
          .deleteAll(db)
        for tag in Set(tags) {
          try DefaultUploadTagRecord(serverId: serverID, tagId: tag).insert(db)
        }
      }
    }
  }
}
