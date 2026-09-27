import DataModel
import Foundation

@testable import Persistence

/// The pre-split write API, for tests that build a cache state rather than
/// exercise a race: a rewrite takes the key's current generation as its basis.
extension Database {
  func writeQueryPage(
    queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int, totalCount: UInt?, replaceAll: Bool
  ) async throws {
    if replaceAll {
      try await replaceQueryPage(
        queryKey: queryKey, serverID: serverID, documents: documents, totalCount: totalCount,
        basis: queryOrderGeneration(queryKey: queryKey, serverID: serverID))
    } else {
      try await appendQueryPage(
        queryKey: queryKey, serverID: serverID, documents: documents,
        startPosition: startPosition, totalCount: totalCount)
    }
  }

  func replaceQueryOrder(queryKey: QueryKey, serverID: UUID, orderedIDs: [UInt]) async throws {
    try await replaceQueryOrder(
      queryKey: queryKey, serverID: serverID, orderedIDs: orderedIDs,
      basis: queryOrderGeneration(queryKey: queryKey, serverID: serverID))
  }
}
