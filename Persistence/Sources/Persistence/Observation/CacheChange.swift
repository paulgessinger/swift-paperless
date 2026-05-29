import Foundation

/// A coarse signal that the local element cache changed and the store should
/// re-hydrate. Emitted by ``Database/observeElements()`` (backed by GRDB
/// `DatabaseRegionObservation`), so it captures writes from *any* in-process
/// writer — sync, write-through mutation, or a background task — and can't be
/// forgotten at an individual call site.
///
/// Stage 7 is single-active-server: the change does not carry a `serverID` yet.
/// Multi-server sync (Stage 10) adds the originating server so the store can
/// filter to the active one.
public enum CacheChange: Sendable, Equatable {
  /// One or more element collections changed. `kinds` is best-effort: when the
  /// observation can't attribute the write to specific tables it reports the
  /// full set, and the store hydrates each kind (a cheap cache read).
  case elements(kinds: Set<ElementKind>)
}

/// The small, replayable element collections cached locally.
public enum ElementKind: String, Sendable, Hashable, CaseIterable {
  case tag
  case correspondent
  case documentType
  case storagePath
  case savedView
  case user
  case group
  case customField
  case uiSettings
  case serverConfiguration
}
