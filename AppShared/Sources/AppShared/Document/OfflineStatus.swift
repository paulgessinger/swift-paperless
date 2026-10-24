//
//  OfflineStatus.swift
//  AppShared
//
//  The Offline & Sync screen's figures for one server, observed from the
//  database for as long as the screen holds them rather than for the whole
//  life of the server's projection: some of them re-run their query on every
//  file a library download writes.
//

import Common
import DataModel
import Foundation
import Persistence

@MainActor
@Observable
public final class OfflineStatus {
  /// When this server's library was last fully filled, `nil` if never. From
  /// `server_sync_state.library_coverage_at`, so the screen tracks fills and
  /// a cache wipe, which clears it.
  public private(set) var libraryCoverageAt: Date?

  /// When the reconcile last refreshed something for this server, `nil` if
  /// never: passes the scheduler runs as well, and across relaunches.
  public private(set) var lastRefreshedAt: Date?

  /// Views, saved or default, whose proactive fill the server most recently
  /// rejected, so the screen can warn that they aren't fully cached.
  public private(set) var syncErrors: [QuerySyncError] = []

  /// The server's cached `document` rows. Throttled: a fill writes a page at
  /// a time.
  public private(set) var cachedDocumentCount = 0

  /// How many of the library's archives are on the device, from the file
  /// index. Throttled: every finished download changes it.
  public private(set) var libraryFileProgress: LibraryFileProgress = .zero

  /// How many of the kept documents have their archive on the device, those
  /// kept by a saved view included. Throttled, like the library's.
  public private(set) var keptOfflineFileProgress: LibraryFileProgress = .zero

  /// The same figures for each kept saved view, by saved-view id. Throttled.
  public private(set) var keptOfflineViewProgress: [UInt: LibraryFileProgress] = [:]

  public let serverID: UUID

  @ObservationIgnored private let observationTasks = TaskBox()

  public init(database: Database, serverID: UUID) {
    self.serverID = serverID
    observationTasks.replace(with: [
      observationLoop(
        database.observeLibraryCoverageAt(serverID: serverID), into: \.libraryCoverageAt,
        of: self),
      observationLoop(
        database.observeLastRefreshedAt(serverID: serverID), into: \.lastRefreshedAt, of: self),
      observationLoop(
        database.observeQuerySyncErrors(serverID: serverID), into: \.syncErrors, of: self),
      observationLoop(
        database.observeDocumentCount(serverID: serverID), into: \.cachedDocumentCount,
        of: self, throttle: UpdateThrottle()),
      observationLoop(
        database.observeLibraryFileProgress(serverID: serverID, scope: .library),
        into: \.libraryFileProgress, of: self, throttle: UpdateThrottle()),
      observationLoop(
        database.observeLibraryFileProgress(serverID: serverID, scope: .keptOffline),
        into: \.keptOfflineFileProgress, of: self, throttle: UpdateThrottle()),
      observationLoop(
        database.observeKeptOfflineViewProgress(serverID: serverID),
        into: \.keptOfflineViewProgress, of: self, throttle: UpdateThrottle()),
    ])
  }

  deinit {
    observationTasks.cancelAll()
  }
}
