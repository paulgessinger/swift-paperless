//
//  ServerProjection.swift
//  AppShared
//
//  The source-of-truth read projection for one server. Owned by
//  `DocumentStore`, which re-exposes it through read-only computed delegates
//  (`store.tags { projection?.tags ?? [:] }`) so existing call sites keep
//  working.
//
//  The DB is the only authoritative copy. Each collection/singleton is kept
//  live by a GRDB `ValueObservation` (vended as a typed `observe…` stream from
//  `Persistence`): the observation *carries the data* (the freshly-mapped domain
//  result), which the loop assigns directly — there is no `hydrate` step and no
//  coarse `CacheChange` signal. The first emission is the current cached state
//  (offline-first instant paint), then live updates as `sync`/mutations write
//  the DB.
//
//  One instance belongs to one server for its whole life: it is created with
//  the `(database, serverID)` it observes, starts its loops in `init`, and
//  cancels them in `deinit`. Switching servers *replaces* the instance rather
//  than re-pointing it, which is what makes a stale emission harmless — the
//  loop that produced it can only write into the object it was born with, and
//  nothing reads that object any more.
//

import Common
import DataModel
import Foundation
import Persistence
import SwiftUI
import os

@MainActor
@Observable
public final class ServerProjection {
  // MARK: Observed projection (read-only; written only by the observation loops)

  public private(set) var tags: [UInt: Tag] = [:]
  public private(set) var correspondents: [UInt: Correspondent] = [:]
  public private(set) var documentTypes: [UInt: DocumentType] = [:]
  public private(set) var storagePaths: [UInt: StoragePath] = [:]
  public private(set) var savedViews: [UInt: SavedView] = [:]
  public private(set) var users: [UInt: User] = [:]
  public private(set) var groups: [UInt: UserGroup] = [:]
  public private(set) var customFields: [UInt: CustomField] = [:]

  // Derived from the `ui_settings` singleton, set together on each emission.
  public private(set) var currentUser: User?
  public private(set) var permissions: UserPermissions = .empty
  public private(set) var settings = UISettingsSettings()

  public private(set) var serverConfiguration: ServerConfiguration?

  /// True once the `ui_settings` singleton has produced a non-nil value for this
  /// server — i.e. `permissions`/`settings` reflect real data rather than the
  /// cold-cache default. Lets the UI distinguish "loading" from "denied".
  public private(set) var isHydrated = false

  /// The documents kept offline, for the list's badges and the detail view's
  /// toggle.
  public private(set) var keptOfflineDocumentIDs: Set<UInt> = []

  /// The saved views kept offline, for the view's toggle and badge.
  public private(set) var keptOfflineViewIDs: Set<UInt> = []

  // MARK: Members

  @ObservationIgnored
  private let database: Database

  /// The server this projection is pinned to for its whole life.
  @ObservationIgnored
  public let serverID: UUID

  /// The live observation loops, held in a locked box rather than a stored
  /// property because `deinit` is nonisolated and cannot read main-actor state.
  /// `Task.cancel()` is safe from any thread, so the box only has to make the
  /// list itself safe to touch.
  @ObservationIgnored
  private let observationTasks = TaskBox()

  // MARK: Lifecycle

  /// Start observing `serverID`'s cached data. A fresh instance is born empty,
  /// which is what a caller switching servers wants: the previous server's data
  /// is gone the moment the instance is replaced, without a separate clearing
  /// step to keep in sync with the loops.
  public init(database: Database, serverID: UUID) {
    self.database = database
    self.serverID = serverID
    observationTasks.replace(with: [
      observe(database.observeElements(TagRecord.self, serverID: serverID), into: \.tags),
      observe(
        database.observeElements(CorrespondentRecord.self, serverID: serverID),
        into: \.correspondents),
      observe(
        database.observeElements(DocumentTypeRecord.self, serverID: serverID),
        into: \.documentTypes),
      observe(
        database.observeElements(StoragePathRecord.self, serverID: serverID),
        into: \.storagePaths),
      observe(
        database.observeElements(SavedViewRecord.self, serverID: serverID), into: \.savedViews),
      observe(database.observeElements(UserRecord.self, serverID: serverID), into: \.users),
      observe(database.observeElements(UserGroupRecord.self, serverID: serverID), into: \.groups),
      observe(
        database.observeElements(CustomFieldRecord.self, serverID: serverID),
        into: \.customFields),
      observeUISettings(database.observeUISettings(serverID: serverID)),
      observeValue(
        database.observeServerConfiguration(serverID: serverID), into: \.serverConfiguration),
      observeValue(
        database.observeKeptOfflineIDs(serverID: serverID), into: \.keptOfflineDocumentIDs),
      observeValue(
        database.observeKeptOfflineViewIDs(serverID: serverID), into: \.keptOfflineViewIDs),
    ])
  }

  deinit {
    observationTasks.cancelAll()
  }

  /// Pull the `ui_settings` singleton from the DB into the projection, for the
  /// one caller (`DocumentStore.fetchUISettings`) that reads `permissions`
  /// immediately after a refresh and cannot wait for the observation's runloop
  /// hop. The observation will re-emit the same values harmlessly. Awaits rather
  /// than blocks: `ui_settings` is a cache table (see `Database+Connections`).
  func refreshUISettings() async {
    guard let uiSettings = try? await database.uiSettings(serverID: serverID) else { return }
    apply(uiSettings)
  }

  // MARK: Observation

  /// A collection observation, keyed by element id for the dictionary shape the
  /// call sites read.
  private func observe<E: Identifiable & Sendable>(
    _ stream: AsyncThrowingStream<[E], Error>,
    into keyPath: ReferenceWritableKeyPath<ServerProjection, [UInt: E]>
  ) -> Task<Void, Never> where E.ID == UInt {
    Task { @MainActor [weak self] in
      do {
        for try await values in stream {
          guard let self else { break }
          var dict = [UInt: E](minimumCapacity: values.count)
          for value in values { dict[value.id] = value }
          self[keyPath: keyPath] = dict
        }
      } catch is CancellationError {
      } catch {
        Logger.shared.error("Element observation terminated: \(error)")
      }
    }
  }

  /// Whatever the stream carries, assigned as it arrives: a singleton, a
  /// list that isn't keyed by id.
  private func observeValue<V: Sendable>(
    _ stream: AsyncThrowingStream<V, Error>,
    into keyPath: ReferenceWritableKeyPath<ServerProjection, V>
  ) -> Task<Void, Never> {
    observationLoop(stream, into: keyPath, of: self)
  }

  private func observeUISettings(
    _ stream: AsyncThrowingStream<UISettings?, Error>
  ) -> Task<Void, Never> {
    Task { @MainActor [weak self] in
      do {
        for try await value in stream {
          guard let self else { break }
          // A nil emission means a cold cache: keep the prior values (don't
          // reset permissions to .empty mid-session) and leave isHydrated false
          // so the UI can show "loading" rather than "denied".
          if let value { apply(value) }
        }
      } catch is CancellationError {
      } catch {
        Logger.shared.error("UI settings observation terminated: \(error)")
      }
    }
  }

  private func apply(_ uiSettings: UISettings) {
    currentUser = uiSettings.user
    permissions = uiSettings.permissions
    settings = uiSettings.settings
    isHydrated = true
  }
}
