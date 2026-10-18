//
//  OfflineSyncView.swift
//  swift-paperless
//
//  Central place to control and observe offline caching: the browsing-scope
//  setting, the current sync/fill status, how much data the background
//  processes have moved (to inform Wi‑Fi gating), and how much space it all
//  takes on disk.
//

import AppShared
import DataModel
import Networking
import Persistence
import SwiftUI

public struct OfflineSyncView: View {
  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager
  // Optional to match `SettingsView`, which declares it the same way — the
  // SettingsView preview injects no monitor, and a non-optional read traps as
  // soon as the preview navigates here.
  @Environment(NetworkMonitor.self) private var networkMonitor: NetworkMonitor?
  @EnvironmentObject private var errorController: ErrorController
  @State private var stats = TransferStatistics.shared
  @State private var downgradeRequested = false
  /// The server's total for the default list, read once from the cached query
  /// status. Only used to decide whether to suggest *Entire library*.
  @State private var libraryTotal: UInt?

  /// Whether *this* button's action is still running. `store.isSyncing` covers
  /// work the session has in flight, but there are brief moments between the
  /// phases this action drives where no slot is occupied; without this the
  /// button would blink back to enabled part-way through its own run.
  @State private var syncNowRunning = false

  /// The active server's figures, observed while this screen is up.
  @State private var status: OfflineStatus?

  private var libraryFileProgress: LibraryFileProgress { status?.libraryFileProgress ?? .zero }
  private var syncErrors: [QuerySyncError] { status?.syncErrors ?? [] }

  public init() {}

  // The active server's mode, read/written through ConnectionManager (persisted
  // on the connection record). The setting is per-server.
  private var mode: OfflineBrowsingMode { connectionManager.activeOfflineBrowsingMode }

  /// What a proactive pass on the active server would run right now — the same
  /// question `SyncPlan` answers for every other server, asked here rather than
  /// re-derived, so this screen can't disagree with the sweep about its own
  /// server. Absent monitor (the SettingsView preview injects none) reads as an
  /// unrestricted link, so the preview renders the ordinary state rather than
  /// the "waiting for Wi-Fi" one.
  private var plannedPhases: SyncPhases {
    SyncPlan.phases(
      isEntireLibrary: mode == .entireLibrary,
      condition: SyncCondition(
        cost: networkMonitor?.cost ?? .unrestricted,
        syncOverCellular: connectionManager.activeSyncOverCellular))
  }

  /// Suggest the greedy mode only when it is actually cheap. A new server starts
  /// at *Recently browsed* whatever its size — downloading a whole library is
  /// the user's call — so this is where the size heuristic earns its keep.
  /// Work is running — this button's own action, or anything else driving the
  /// active server's session (a lifecycle sweep, a background run).
  private var syncNowBusy: Bool { syncNowRunning || store.isSyncing }

  private var recommendsEntireLibrary: Bool {
    mode == .recentlyBrowsed && OfflineLibrarySize.isSmall(documentCount: libraryTotal)
  }

  /// *Entire library* is on, but the link won't currently carry the fill — the
  /// difference between "nothing to do" and "not now", which the screen used to
  /// render identically as Idle.
  private var waitingForNetwork: Bool {
    mode == .entireLibrary && !plannedPhases.contains(.fill) && !store.isSyncing
  }

  public var body: some View {
    Form {
      Section {
        Picker(
          selection: Binding(
            get: { connectionManager.activeOfflineBrowsingMode },
            set: { newMode in
              // Leaving Entire library reclaims the cache, which is destructive
              // and can't be undone short of downloading it all again. Confirm
              // first; until then the picker snaps back, because `get:` still
              // reads the unchanged stored mode.
              if connectionManager.activeOfflineBrowsingMode == .entireLibrary,
                newMode == .recentlyBrowsed
              {
                downgradeRequested = true
              } else {
                connectionManager.setOfflineBrowsingMode(newMode)
                if newMode == .entireLibrary {
                  Task { await store.fillIfEnabled(phases: plannedPhases, force: true) }
                }
              }
            })
        ) {
          ForEach(OfflineBrowsingMode.allCases, id: \.self) { mode in
            Text(mode.localizedName).tag(mode)
          }
        } label: {
          Text(.settings(.offlineBrowsingModeLabel))
        }
        .confirmationDialog(
          String(localized: .settings(.offlineBrowsingDowngradeTitle)),
          isPresented: $downgradeRequested,
          titleVisibility: .visible
        ) {
          Button(
            String(localized: .settings(.offlineBrowsingDowngradeConfirm)), role: .destructive
          ) {
            connectionManager.setOfflineBrowsingMode(.recentlyBrowsed)
          }

          Button(String(localized: .app(.cancel)), role: .cancel) {}
        } message: {
          Text(.settings(.offlineBrowsingDowngradeMessage))
        }
      } header: {
        Text(.settings(.offlineBrowsingModeHeader))
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text(.settings(.offlineBrowsingModeDescription))
          if recommendsEntireLibrary {
            Text(.settings(.offlineBrowsingModeRecommendation))
          }
        }
      }

      Section {
        Toggle(
          isOn: Binding(
            get: { connectionManager.activeSyncOverCellular },
            set: { connectionManager.setSyncOverCellular($0) })
        ) {
          Text(.settings(.offlineSyncCellularLabel))
        }
      } footer: {
        Text(.settings(.offlineSyncCellularDescription))
      }

      Section {
        // One row per running stage, in a fixed order. They overlap — a
        // reconcile is usually still going when a fill starts — so showing only
        // the "main" one hid work that was genuinely in progress. Each row is a
        // single cell so its bar and caption sit under its own label rather than
        // carrying a separator of their own.
        if store.syncActivities.isEmpty {
          statusRow(String(localized: .settings(.offlineSyncActivity)), value: activityText)
        } else {
          ForEach(store.syncActivities) { activity in
            let activity = displayed(activity)
            // The label on a line of its own and the count on the caption
            // line: side by side, a growing count wrapped the row back and
            // forth between one line and two.
            VStack(alignment: .leading, spacing: 8) {
              Text(stageLabel(for: activity.stage))
              // `nil` fraction ⇒ indeterminate, for a stage that hasn't worked
              // out its total yet.
              ActivityBar(fraction: activity.fraction)
              HStack(alignment: .firstTextBaseline) {
                activityCaption(for: activity)
                  .lineLimit(1)
                Spacer(minLength: 8)
                if let total = activity.total {
                  Text(
                    progressCountText(
                      for: activity.stage, completed: activity.completed, total: total)
                  )
                  .monospacedDigit()
                  .fixedSize()
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
          }
        }
        if mode == .entireLibrary {
          dateStatusRow(
            String(localized: .settings(.offlineSyncLastFullFill)), date: status?.libraryCoverageAt)
          // From the file index, so it reads right after a relaunch, while
          // the download row above only shows while tasks are in flight.
          statusRow(
            String(localized: .settings(.offlineSyncFilesDownloaded)),
            value: String(
              localized: .settings(
                .offlineSyncFilesDownloadedValue(
                  libraryFileProgress.downloadedFiles,
                  libraryFileProgress.totalDocuments,
                  libraryFileProgress.downloadedBytes.formatted(.byteCount(style: .file))))))
        }
        if (status?.keptOfflineFileProgress ?? .zero).totalDocuments > 0 {
          let progress = (status?.keptOfflineFileProgress ?? .zero)
          statusRow(
            String(localized: .settings(.offlineSyncKeptOffline)),
            value: String(
              localized: .settings(
                .offlineSyncFilesDownloadedValue(
                  progress.downloadedFiles, progress.totalDocuments,
                  progress.downloadedBytes.formatted(.byteCount(style: .file))))))
        }
        dateStatusRow(
          String(localized: .settings(.offlineSyncLastRefresh)), date: status?.lastRefreshedAt)
        statusRow(
          String(localized: .settings(.offlineSyncCachedDocuments)),
          value: (status?.cachedDocumentCount ?? 0).formatted())

        Button {
          Task {
            // Explicit user action: bypass the reconcile throttle and the
            // link gate, and force a re-fill ignoring the freshness marker.
            //
            // `userInitiated` makes the sync rethrow instead of failing soft,
            // so a failed "Sync now" is reported rather than looking identical
            // to one that worked.
            syncNowRunning = true
            defer { syncNowRunning = false }
            let announcedOffline = errorController.noteOfflineIfNeeded()
            do {
              try await store.sync(userInitiated: true)
            } catch {
              if !announcedOffline {
                errorController.push(readError: error)
              }
            }
            // `.full` rather than the planned phases: this is the user asking
            // for the work outright, so the link gate doesn't apply. Saying so
            // in the phase set beats claiming the network is unmetered when it
            // isn't.
            await store.fillIfEnabled(phases: .full, force: true)
          }
        } label: {
          // Explicit `foregroundStyle`, not just `.disabled`: a `Label`'s icon
          // in a `Form` row button doesn't pick up the row's disabled dimming
          // the way its text does, so a disabled row otherwise reads as a
          // grayed-out title next to a still-accent-coloured icon.
          Label(String(localized: .settings(.offlineSyncNow)), systemImage: "arrow.clockwise")
            .foregroundStyle(syncNowBusy ? Color.secondary : Color.accentColor)
        }
        // Any work on this server, not just the library fill: the detail fill
        // left this enabled, so a second pass could be stacked on a running one.
        .disabled(syncNowBusy)
      } header: {
        Text(.settings(.offlineSyncStatusHeader))
      }
      .labeledContentStyle(StatusRowStyle())

      // Both modes, unlike the per-view list below; empty renders nothing.
      SyncFailuresSection(
        failures: store.syncFailures.filter {
          mode == .entireLibrary || !$0.site.isEntireLibraryOnly
        })

      if mode == .entireLibrary, !syncErrors.isEmpty {
        Section {
          ForEach(syncErrors) { error in
            VStack(alignment: .leading, spacing: 2) {
              Text(error.savedViewName ?? String(localized: .settings(.offlineSyncDefaultView)))
              Text(error.message)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(error.failedAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
        } header: {
          Label(
            String(localized: .settings(.offlineSyncProblemsHeader)),
            systemImage: "exclamationmark.triangle")
        } footer: {
          Text(.settings(.offlineSyncProblemsDescription))
        }
      }

      Section {
        statusRow(String(localized: .settings(.offlineSyncTotal)), value: byteText(stats.total))
        ForEach(TransferCategory.allCases, id: \.self) { category in
          let bytes = stats.bytesByCategory[category] ?? 0
          if bytes > 0 {
            statusRow(category.localizedName, value: byteText(bytes))
          }
        }
        Button(role: .destructive) {
          stats.reset()
        } label: {
          Text(.settings(.offlineSyncResetStatistics))
        }
      } header: {
        Text(.settings(.offlineSyncDataTransferredHeader))
      } footer: {
        // Say what "Total" covers, and that opening a document already in the
        // offline cache costs nothing, so a small Documents row isn't read as
        // the meter missing traffic.
        VStack(alignment: .leading, spacing: 4) {
          Text(.settings(.offlineSyncDataSince(formattedDate(stats.since))))
          Text(.settings(.offlineSyncDataScopeAll))
        }
      }

      OfflineStorageSection()
    }
    .task { libraryTotal = await store.libraryDocumentCount() }
    .task(id: store.activeServerID) { status = store.makeOfflineStatus() }
    .navigationTitle(Text(.settings(.offlineSyncTitle)))
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func statusRow(_ title: String, value: String) -> some View {
    // `LabeledContent`, not a bare HStack + Spacer: it pairs label and value
    // into one accessibility element, which is what the other status rows in
    // this settings tree already do.
    LabeledContent(title) {
      Text(value).foregroundStyle(.secondary)
    }
  }

  private func stageLabel(for stage: SyncActivity.Stage) -> String {
    switch stage {
    case .libraryFill: String(localized: .settings(.offlineSyncFilling))
    case .detailFill: String(localized: .settings(.offlineSyncDetailFill))
    case .fileDownload: String(localized: .settings(.offlineSyncFileDownload))
    case .reconcile: String(localized: .settings(.offlineSyncReconciling))
    case .elementSync: String(localized: .settings(.offlineSyncRefreshing))
    }
  }

  /// The reconcile stage counts changed documents, not documents overall —
  /// "3 of 15" reads as meaningless there (of *what*?) where it's obvious for
  /// the other stages from their label. Only that stage gets a labeled count.
  private func progressCountText(for stage: SyncActivity.Stage, completed: Int, total: Int)
    -> LocalizedStringResource
  {
    switch stage {
    case .reconcile: .settings(.offlineSyncReconcileProgressCount(completed, total))
    case .fileDownload: .settings(.offlineSyncFileProgressCount(completed, total))
    case .libraryFill, .detailFill, .elementSync:
      .settings(.offlineSyncProgressCount(completed, total))
    }
  }

  /// Only reached when nothing is running — the stage rows speak for themselves
  /// otherwise. Says *why* it's not running where there's a reason to give.
  private var activityText: String {
    if store.libraryFilesPausedLowStorage {
      String(localized: .settings(.offlineSyncPausedLowStorage))
    } else if waitingForNetwork {
      String(localized: .settings(.offlineSyncWaitingForWifi))
    } else {
      String(localized: .settings(.offlineSyncIdle))
    }
  }

  /// What the downloads cover: the whole library in *Entire library*, the
  /// kept documents otherwise, as the downloader scopes them.
  private var downloadProgress: LibraryFileProgress {
    mode == .entireLibrary
      ? libraryFileProgress : (status?.keptOfflineFileProgress ?? .zero)
  }

  /// The download row counts from the file index, the same figure as the
  /// files row below it, so the two never disagree mid-download.
  private func displayed(_ activity: SyncActivity) -> SyncActivity {
    guard activity.stage == .fileDownload else { return activity }
    var activity = activity
    activity.completed = downloadProgress.downloadedFiles
    activity.total = downloadProgress.totalDocuments
    return activity
  }

  @ViewBuilder
  private func activityCaption(for activity: SyncActivity) -> some View {
    if let detail = activity.detail {
      Text(detail)
    } else if activity.stage == .libraryFill {
      // `nil` here means "on the default list" (a saved view's name is never
      // nil), not "no detail to show" — say so, rather than leaving the
      // caption blank while it's already working.
      Text(.settings(.offlineSyncDefaultView))
    } else if activity.stage == .fileDownload {
      Text(fileDownloadCaption)
    }
  }

  /// Under the download row: what is on the device and how many files are
  /// moving, or why none are.
  private var fileDownloadCaption: String {
    if store.libraryFilesPausedLowStorage {
      return String(localized: .settings(.offlineSyncPausedLowStorage))
    }
    return String(
      localized: .settings(
        .offlineSyncFileDownloadDetail(
          downloadProgress.downloadedBytes.formatted(.byteCount(style: .file)),
          store.libraryFilesInFlight)))
  }

  @ViewBuilder
  private func dateStatusRow(_ title: String, date: Date?) -> some View {
    // `Text(_:style:)`, not a formatted string: SwiftUI keeps this text live,
    // ticking the relative offset up on its own, where a formatted string only
    // updates the next time something else redraws this view.
    LabeledContent(title) {
      if let date {
        Text(date, style: .relative)
          .foregroundStyle(.secondary)
      } else {
        Text(.settings(.offlineSyncNever))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func formattedDate(_ date: Date) -> String {
    date.formatted(date: .numeric, time: .shortened)
  }

  private func byteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

/// Label and value on one line whatever the value's length, so a count that
/// grows doesn't wrap the row; stacked only at accessibility text sizes,
/// where one line would not fit.
private struct StatusRowStyle: LabeledContentStyle {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func makeBody(configuration: Configuration) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 2) {
        configuration.label
        configuration.content
      }
      .accessibilityElement(children: .combine)
    } else {
      HStack(alignment: .firstTextBaseline) {
        configuration.label
          .lineLimit(1)
        Spacer(minLength: 8)
        configuration.content
          .lineLimit(1)
          .monospacedDigit()
          .layoutPriority(1)
      }
      .accessibilityElement(children: .combine)
    }
  }
}

/// A linear bar whose advance animates across the display cadence, so it
/// moves on between the throttled updates. Drawn rather than a
/// `ProgressView`, which jumps to each new value whatever the animation.
private struct ActivityBar: View {
  /// `nil` is indeterminate.
  let fraction: Double?

  var body: some View {
    if let fraction {
      Capsule()
        .fill(.quaternary)
        .overlay {
          Capsule()
            .fill(.tint)
            .scaleEffect(x: min(max(fraction, 0), 1), anchor: .leading)
        }
        .clipShape(Capsule())
        .frame(height: 4)
        .animation(.linear(duration: 0.45), value: fraction)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    } else {
      ProgressView()
        .progressViewStyle(.linear)
    }
  }
}
