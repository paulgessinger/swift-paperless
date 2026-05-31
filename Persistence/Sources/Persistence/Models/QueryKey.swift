import CryptoKit
import DataModel
import Foundation

/// Stable identity of a *cached query* — the key under which a list's ordered
/// membership is stored in `query_order` / `query_meta`.
///
/// The list is not always a saved view: it can be the default list, a saved view
/// with the user's sort changed, or a saved view plus an ad-hoc filter — each of
/// which the server answers with a *different ordered membership*. So a
/// server-replay query derives its key by hashing the **effective server query**
/// (the filter rules' query items + the sort), which is exactly what determines
/// the server's response. Keying on a saved-view id instead would collide all of
/// those.
///
/// Two notes on correctness:
/// - The hash is **CryptoKit `SHA256`**, not Swift's `Hasher` — `Hasher` is
///   seeded per process, so a `Hasher`-derived key would change every launch and
///   never match yesterday's cached rows.
/// - The canonical input is `FilterRule.queryItems(for:)` (which already sorts
///   multi-value rule values) re-sorted as `name=value` lines, so it is
///   independent of dictionary iteration order and of the transient
///   `FilterState.modified` flag (which is not a query parameter).
///
/// Virtual / client-defined views (e.g. Stage 14's pinned "Downloaded" list) use
/// a ``init(sentinel:)`` well-known key instead of a hash, since they have no
/// server query to replay.
public struct QueryKey: Hashable, Sendable {
  public let rawValue: String

  public init(serverID: UUID, filter: FilterState) {
    let ordering = (filter.sortOrder.reverse ? "-" : "") + filter.sortField.rawValue
    let ruleLines =
      FilterRule.queryItems(for: filter.rules)
      .map { "\($0.name)=\($0.value ?? "")" }
      .sorted()
    let canonical = (["ordering=\(ordering)"] + ruleLines).joined(separator: "\n")

    var hasher = SHA256()
    hasher.update(data: Data(serverID.uuidString.utf8))
    hasher.update(data: Data([0]))  // domain separator
    hasher.update(data: Data(canonical.utf8))
    rawValue = hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  /// A well-known, non-hashed key for a virtual/local view.
  public init(sentinel: String) {
    rawValue = sentinel
  }
}
