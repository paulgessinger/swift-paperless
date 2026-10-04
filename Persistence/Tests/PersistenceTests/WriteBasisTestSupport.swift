import DataModel
import Foundation

@testable import Persistence

// Shorthands for tests that don't exercise the deletion log: a basis that
// nothing was deleted after, and writes based on a mark taken just now.

extension QueryWriteBasis {
  static let initial = QueryWriteBasis(
    generation: .initial, deletions: DocumentDeletionMark(sequence: .max))
}

extension Persistence.Database {
  @discardableResult
  func applyChangedDocuments(_ domains: [Document], serverID: UUID) async throws -> Int {
    try await applyChangedDocuments(domains, serverID: serverID, deletions: documentDeletionMark())
  }

  func appendQueryPage(
    queryKey: QueryKey, serverID: UUID, documents: [Document],
    startPosition: Int, totalCount: UInt?
  ) async throws {
    try await appendQueryPage(
      queryKey: queryKey, serverID: serverID, documents: documents,
      startPosition: startPosition, totalCount: totalCount, deletions: documentDeletionMark())
  }
}
