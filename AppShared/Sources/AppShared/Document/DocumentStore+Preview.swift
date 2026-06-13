//
//  DocumentStore+Preview.swift
//  AppShared
//
//  Preview/test convenience for building a `DocumentStore` under the
//  source-of-truth model, where every repository must front a DB for the
//  element projection to see anything.
//

import Foundation
import Networking
import Persistence

extension DocumentStore {
  /// A store backed by an in-memory seeded DB, wrapping `wrapped` in a
  /// `CachingRepository` so the live `ElementStore` projection and the
  /// write-through mutations behave exactly as in production.
  ///
  /// The wrapped repository's element data is copied into the DB by a one-shot
  /// `fetchAll()` (previews are live, so it lands a beat after first render);
  /// `PreviewRepository`'s built-in fixtures appear this way. Previews using a
  /// `TransientRepository` seed through `store.repository` (writes flow to the
  /// DB) and recover the underlying repository for its non-`Repository` helpers
  /// via ``previewRepository(as:)``.
  @MainActor
  public static func preview(_ wrapped: some Repository = PreviewRepository()) -> DocumentStore {
    let serverID = UUID()
    let database: Database
    do {
      database = try Database.seeded(serverID: serverID)
    } catch {
      // The in-memory seed (DatabaseQueue + migrations) is infallible in
      // practice; a preview crash here is loud and immediately actionable.
      preconditionFailure("Preview database seed failed: \(error)")
    }
    let caching = CachingRepository(wrapping: wrapped, database: database, serverID: serverID)
    let store = DocumentStore(repository: caching)
    Task { try? await store.fetchAll() }
    return store
  }

  /// Recover the underlying repository from a store built by ``preview(_:)`` —
  /// for previews that need a concrete repository's preview-only helpers (e.g.
  /// `TransientRepository.addUser`/`login`/`allDocuments`). The protocol
  /// surface should be used through `store.repository` so writes reach the DB.
  @MainActor
  public func previewRepository<R: Repository>(as type: R.Type) -> R {
    guard let caching = repository as? CachingRepository<R> else {
      preconditionFailure("previewRepository(as:) called on a store not built by preview(_:)")
    }
    return caching.wrapped
  }
}
