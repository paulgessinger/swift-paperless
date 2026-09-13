import Foundation
import GRDB

/// One ordered membership entry of a cached query (`query_order` table).
/// `position` is the server-order index (0-based, gappy after a deletion — gaps
/// are made invisible by windowing on ordered row offset, not by renumbering).
struct QueryOrderRow: FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable
{
  static let databaseTableName = "query_order"

  var serverId: UUID
  var queryKey: String
  var position: Int
  var remoteId: UInt

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case queryKey = "query_key"
    case position
    case remoteId = "remote_id"
  }
}

/// Per-query bookkeeping (`query_meta` table): the server-reported total (which
/// survives local deletion gaps) and the order-stale flag a mutation sets when
/// it changes a field under the active sort.
struct QueryMetaRow: FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable, Equatable {
  static let databaseTableName = "query_meta"

  var serverId: UUID
  var queryKey: String
  var totalCount: UInt?
  var orderStale: Bool
  var filledAt: Date?

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case queryKey = "query_key"
    case totalCount = "total_count"
    case orderStale = "order_stale"
    case filledAt = "filled_at"
  }
}

/// When a list was last put on screen (`query_meta.viewed_at`), as a record of
/// its own over the same table.
///
/// Kept off ``QueryMetaRow`` on purpose. A record's `upsert` sets only the
/// columns it encodes, so every page write leaves this stamp alone, and stamping
/// leaves the fill bookkeeping alone. Nothing has to carry either forward.
struct QueryViewedRow: FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable,
  Equatable
{
  static let databaseTableName = "query_meta"

  var serverId: UUID
  var queryKey: String
  var viewedAt: Date?

  enum CodingKeys: String, CodingKey {
    case serverId = "server_id"
    case queryKey = "query_key"
    case viewedAt = "viewed_at"
  }
}

/// Public status of a cached query, surfaced to the list view-model: the
/// server's `totalCount` (what the count pill shows — the list renders only the
/// locally-loaded prefix, so this is not a scroll extent), how many rows are
/// locally present (`localCount`, reflects deletion gaps), whether the cached
/// order is stale under the active sort, and whether it is the query's complete
/// membership.
public struct QueryStatus: Equatable, Sendable {
  public var totalCount: UInt?
  public var localCount: Int
  public var orderStale: Bool
  /// A fill paged this query to the end (`query_meta.filled_at` is stamped) and
  /// nothing has cut its tail since. `false` for a never-filled key, for one
  /// whose last fill stopped short (page 1's replace clears the stamp, so only a
  /// fill that reaches the end sets it again), and for one a storage cap
  /// truncated (the stamp survives that, but the order no longer reaches the
  /// total). The list uses this to tell a truncated cache from a complete one
  /// when its fill fails.
  public var isComplete: Bool

  public init(totalCount: UInt?, localCount: Int, orderStale: Bool, isComplete: Bool = false) {
    self.totalCount = totalCount
    self.localCount = localCount
    self.orderStale = orderStale
    self.isComplete = isComplete
  }
}
