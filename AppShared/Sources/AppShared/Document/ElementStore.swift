//
//  ElementStore.swift
//  AppShared
//
//  The source-of-truth read projection for the element collections. Owned by
//  `DocumentStore`, which re-exposes these through read-only computed delegates
//  (`store.tags { elementStore.tags }`) so existing call sites keep working.
//
//  The DB is the only authoritative copy. Each collection/singleton is kept
//  live by a GRDB `ValueObservation` (vended as a typed `observe…` stream from
//  `Persistence`): the observation *carries the data* (the freshly-mapped domain
//  result), which the loop assigns directly — there is no `hydrate` step and no
//  coarse `CacheChange` signal. The first emission is the current cached state
//  (offline-first instant paint), then live updates as `sync`/mutations write
//  the DB.
//

import Common
import DataModel
import Foundation
import Persistence
import SwiftUI
import os

@MainActor
@Observable
public final class ElementStore {
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

  /// True once the `ui_settings` singleton has produced a non-nil value for the
  /// active server — i.e. `permissions`/`settings` reflect real data rather than
  /// the cold-cache default. Lets the UI distinguish "loading" from "denied".
  public private(set) var isHydrated = false

  @ObservationIgnored
  private nonisolated(unsafe) var observationTasks: [Task<Void, Never>] = []

  public init() {}

  deinit {
    for task in observationTasks { task.cancel() }
  }

  // MARK: Lifecycle

  /// Point the projection at a server's cached data and keep it live. Cancels
  /// any prior observation, clears the dicts synchronously (so the previous
  /// server's data isn't shown during the gap before the first emission lands),
  /// then subscribes. Mirror of `set(repository:)`'s connection-switch hook.
  public func repoint(database: Database, serverID: UUID) {
    cancelObservation()
    clearProjection()
    start(database: database, serverID: serverID)
  }

  /// Detach from any server (logout / a non-caching repository that fronts no
  /// DB): stop the loops and clear the projection.
  public func reset() {
    cancelObservation()
    clearProjection()
  }

  /// Synchronously pull the `ui_settings` singleton from the DB into the
  /// projection, for the one caller (`DocumentStore.fetchUISettings`) that reads
  /// `permissions` immediately after a refresh and cannot wait for the
  /// observation's runloop hop. The observation will re-emit the same values
  /// harmlessly.
  func refreshUISettings(from database: Database, serverID: UUID) {
    guard let uiSettings = try? database.uiSettings(serverID: serverID) else { return }
    apply(uiSettings)
  }

  // MARK: Observation

  private func start(database: Database, serverID: UUID) {
    observationTasks = [
      observeCollection(
        database.observeElements(TagRecord.self, serverID: serverID), into: \.tags),
      observeCollection(
        database.observeElements(CorrespondentRecord.self, serverID: serverID),
        into: \.correspondents),
      observeCollection(
        database.observeElements(DocumentTypeRecord.self, serverID: serverID),
        into: \.documentTypes),
      observeCollection(
        database.observeElements(StoragePathRecord.self, serverID: serverID),
        into: \.storagePaths),
      observeCollection(
        database.observeElements(SavedViewRecord.self, serverID: serverID), into: \.savedViews),
      observeCollection(
        database.observeElements(UserRecord.self, serverID: serverID), into: \.users),
      observeCollection(
        database.observeElements(UserGroupRecord.self, serverID: serverID), into: \.groups),
      observeCollection(
        database.observeElements(CustomFieldRecord.self, serverID: serverID),
        into: \.customFields),
      observeUISettings(database.observeUISettings(serverID: serverID)),
      observeSingleton(
        database.observeServerConfiguration(serverID: serverID), into: \.serverConfiguration),
    ]
  }

  private func observeCollection<E: Identifiable & Sendable>(
    _ stream: AsyncThrowingStream<[E], Error>,
    into keyPath: ReferenceWritableKeyPath<ElementStore, [UInt: E]>
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

  private func observeSingleton<V: Sendable>(
    _ stream: AsyncThrowingStream<V?, Error>,
    into keyPath: ReferenceWritableKeyPath<ElementStore, V?>
  ) -> Task<Void, Never> {
    Task { @MainActor [weak self] in
      do {
        for try await value in stream {
          guard let self else { break }
          self[keyPath: keyPath] = value
        }
      } catch is CancellationError {
      } catch {
        Logger.shared.error("Singleton observation terminated: \(error)")
      }
    }
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

  // MARK: Helpers

  private func cancelObservation() {
    for task in observationTasks { task.cancel() }
    observationTasks = []
  }

  private func clearProjection() {
    tags = [:]
    correspondents = [:]
    documentTypes = [:]
    storagePaths = [:]
    savedViews = [:]
    users = [:]
    groups = [:]
    customFields = [:]
    currentUser = nil
    permissions = .empty
    settings = UISettingsSettings()
    serverConfiguration = nil
    isHydrated = false
  }
}
