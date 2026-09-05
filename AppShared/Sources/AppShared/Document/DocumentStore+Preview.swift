//
//  DocumentStore+Preview.swift
//  AppShared
//
//  Preview/test convenience for building a `DocumentStore` under the
//  source-of-truth model, where every repository must front a DB for the
//  element projection to see anything.
//

import DataModel
import Foundation
import Networking
import Persistence

extension DocumentStore {
  /// A store backed by an in-memory seeded DB, wrapping `wrapped` in a
  /// `CachingRepository` so the live `ServerProjection` and the write-through
  /// mutations behave exactly as in production.
  ///
  /// The wrapped repository's element data is copied into the DB by a one-shot
  /// `sync()` (previews are live, so it lands a beat after first render);
  /// `PreviewRepository`'s built-in fixtures appear this way. Previews using a
  /// `TransientRepository` seed through `store.repository` (writes flow to the
  /// DB) and recover the underlying repository for its non-`Repository` helpers
  /// via ``previewRepository(as:)``.
  ///
  /// The `ui_settings` singleton is seeded with a full permission matrix rather
  /// than left to that sync: every store mutation is permission-checked, and the
  /// sync cannot be what supplies the matrix. It is fire-and-forget, and for a
  /// `TransientRepository` it fails outright — `uiSettings()` rethrows
  /// `noUserLoggedIn` until the preview logs a user in from its own `.task`,
  /// which happens after this sync has already run and found no cached row to
  /// fall back to. A preview that seeds through `store.create(…)` would lose
  /// every element to `PermissionsError`. The matrix is applied synchronously so
  /// it holds from the first render, not a runloop hop later; a later sync
  /// overwrites it with the repository's own settings.
  @MainActor
  public static func preview(_ wrapped: some Repository = PreviewRepository()) -> DocumentStore {
    let serverID = UUID()
    let database: Database
    do {
      database = try Database.seeded(
        serverID: serverID,
        uiSettings: UISettings(user: previewUser, permissions: .full))
    } catch {
      // The in-memory seed (DatabaseQueue + migrations) is infallible in
      // practice; a preview crash here is loud and immediately actionable.
      preconditionFailure("Preview database seed failed: \(error)")
    }
    let caching = CachingRepository(wrapping: wrapped, database: database, serverID: serverID)
    // Wrapped in a session like every other store: previews exercise the same
    // ownership path production does, and there is no `init(repository:)` for
    // production code to reach for.
    let store = DocumentStore(session: ServerSession(serverID: serverID, repository: caching))
    // Both awaits, so both go in the task: a preview builds its store in a
    // property initializer and cannot await. The projection repaints as soon as
    // the read lands, which for an in-memory seed is immediate.
    Task {
      await store.projection?.refreshUISettings()
      try? await store.sync()
    }
    return store
  }

  /// Stands in for `ui_settings.user` until a sync supplies the real one. Matches
  /// the user `Database.seeded` puts on the preview connection record.
  private static let previewUser = User(id: 1, isSuperUser: true, username: "preview")

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
