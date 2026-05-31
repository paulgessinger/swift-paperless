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

/// Per-query bookkeeping (`query_meta` table): the server-reported total (the
/// scrollbar extent, which survives local deletion gaps) and the order-stale
/// flag a mutation sets when it changes a field under the active sort.
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

/// Public status of a cached query, surfaced to the list view-model: the
/// server's `totalCount` (scrollbar extent), how many rows are locally present
/// (`localCount`, reflects deletion gaps), and whether the cached order is stale
/// under the active sort.
public struct QueryStatus: Equatable, Sendable {
  public var totalCount: UInt?
  public var localCount: Int
  public var orderStale: Bool

  public init(totalCount: UInt?, localCount: Int, orderStale: Bool) {
    self.totalCount = totalCount
    self.localCount = localCount
    self.orderStale = orderStale
  }
}
