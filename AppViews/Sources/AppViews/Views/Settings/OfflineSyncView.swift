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

  /// Whether the steps are listed: during a pass and shortly after it.
  @State private var stepsVisible = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var libraryFileProgress: LibraryFileProgress { status?.libraryFileProgress ?? .zero }
  private var keptOfflineFileProgress: LibraryFileProgress {
    status?.keptOfflineFileProgress ?? .zero
  }
  private var syncErrors: [QuerySyncError] { status?.syncErrors ?? [] }

  /// Every failed view in *Entire library*, otherwise the kept views: nothing
  /// else is downloaded ahead of time.
  private var visibleSyncErrors: [QuerySyncError] {
    guard mode != .entireLibrary else { return syncErrors }
    guard let serverID = store.activeServerID else { return [] }
    let keptKeys = Set(
      store.keptOfflineViewIDs
        .compactMap { store.savedViews[$0] }
        .map { QueryKey(serverID: serverID, filter: FilterState(savedView: $0)).rawValue })
    return syncErrors.filter { keptKeys.contains($0.queryKey) }
  }

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
    ScrollView {
      VStack(spacing: 0) {
        modeSection
        cellularSection
        statusSection

        // Empty renders nothing.
        SyncFailuresSection(
          failures: store.syncFailures.filter {
            mode == .entireLibrary || !$0.site.isEntireLibraryOnly
          })

        problemsSection
        transferSection
        OfflineStorageSection()
      }
      .labeledContentStyle(StatusRowStyle())
      // On the whole stack, so the sections below the status block move with
      // it as it changes height.
      .animation(
        reduceMotion ? nil : .snappy(duration: 0.35),
        value: SyncStepList.layoutKey(headline: headline, steps: displayedSteps))
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .task { libraryTotal = await store.libraryDocumentCount() }
    .task(id: store.activeServerID) { status = store.makeOfflineStatus() }
    // The steps stay up briefly after the pass, so the last one is seen to
    // finish.
    .task(id: isBusy) {
      if isBusy {
        stepsVisible = true
      } else {
        try? await Task.sleep(for: .seconds(1.5))
        if !Task.isCancelled { stepsVisible = false }
      }
    }
    .navigationTitle(Text(.settings(.offlineSyncTitle)))
    .navigationBarTitleDisplayMode(.inline)
  }

  private var modeSection: some View {
    CustomSection {
      CustomSectionRow {
        LabeledContent {
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
          .labelsHidden()
          .pickerStyle(.menu)
          .tint(.secondary)
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
  }

  private var cellularSection: some View {
    CustomSection {
      CustomSectionRow {
        Toggle(
          isOn: Binding(
            get: { connectionManager.activeSyncOverCellular },
            set: { connectionManager.setSyncOverCellular($0) })
        ) {
          Text(.settings(.offlineSyncCellularLabel))
        }
        // A toggle lays itself out as labeled content; the status rows'
        // baseline alignment would push the switch down.
        .labeledContentStyle(.automatic)
      }
    } footer: {
      Text(.settings(.offlineSyncCellularDescription))
    }
  }

  private var statusSection: some View {
    CustomSection {
      VStack(spacing: 0) {
        SyncStepList(headline: headline, steps: displayedSteps)
        // The download step counts the same files, so the rows that count
        // them step aside while it shows.
        if mode == .recentlyBrowsed || !isDownloading {
          Divider()
          CustomSectionRow { documentsRow }
        }
        keptOfflineRow
        Divider()
        CustomSectionRow {
          dateStatusRow(
            String(localized: .settings(.offlineSyncLastRefresh)), date: status?.lastRefreshedAt)
        }
        Divider()
        CustomSectionRow { syncNowButton }
      }
    } header: {
      Text(.settings(.offlineSyncStatusHeader))
    }
  }

  private var syncNowButton: some View {
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
      Label(String(localized: .settings(.offlineSyncNow)), systemImage: "arrow.clockwise")
        .foregroundStyle(syncNowBusy ? Color.secondary : Color.accentColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Any work on this server, not just the library fill: the detail fill
    // left this enabled, so a second pass could be stacked on a running one.
    .disabled(syncNowBusy)
  }

  @ViewBuilder
  private var problemsSection: some View {
    if !visibleSyncErrors.isEmpty {
      CustomSection {
        VStack(spacing: 0) {
          ForEach(Array(visibleSyncErrors.enumerated()), id: \.element.id) { index, error in
            if index > 0 { Divider() }
            CustomSectionRow {
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
  }

  private var transferSection: some View {
    CustomSection {
      VStack(spacing: 0) {
        CustomSectionRow {
          statusRow(String(localized: .settings(.offlineSyncTotal)), value: byteText(stats.total))
        }
        ForEach(TransferCategory.allCases, id: \.self) { category in
          let bytes = stats.bytesByCategory[category] ?? 0
          if bytes > 0 {
            Divider()
            CustomSectionRow {
              statusRow(category.localizedName, value: byteText(bytes))
            }
          }
        }
        Divider()
        CustomSectionRow {
          Button(role: .destructive) {
            stats.reset()
          } label: {
            Text(.settings(.offlineSyncResetStatistics))
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
        }
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
  }

  // MARK: - Sync steps

  /// Work is running or downloads are in flight, which outlast the step that
  /// queued them.
  private var isBusy: Bool { syncNowBusy || !store.syncActivities.isEmpty }

  /// The stages a pass on this server covers, so the list is complete from
  /// its start.
  private var listedStages: Set<SyncActivity.Stage> {
    var stages: Set<SyncActivity.Stage> = [.elementSync, .reconcile]
    if mode == .entireLibrary {
      stages.formUnion(SyncActivity.Stage.allCases)
    } else if !store.keptOfflineViewIDs.isEmpty || !store.keptOfflineDocumentIDs.isEmpty {
      stages.formUnion([.contentFill, .fileDownload])
    }
    return stages.union(store.syncActivities.map(\.stage))
  }

  private var displayedSteps: [SyncStepDisplay] {
    guard stepsVisible else { return [] }
    return SyncStep.steps(
      for: listedStages, activities: store.syncActivities.map(displayed),
      completed: store.completedSyncStages
    ).map { step in
      var display = SyncStepDisplay(
        id: String(describing: step.stage), title: stepTitle(for: step.stage))
      switch step.state {
      case .pending:
        // A step the finished pass never reported had nothing to do.
        display.state = isBusy ? .pending : .done
      case .done:
        display.state = .done
      case .running:
        display.state = .running
        if let activity = step.activity {
          display.caption = caption(for: activity)
          display.count = countText(for: activity)
          display.fraction = activity.fraction
        }
      }
      return display
    }
  }

  private var headline: SyncHeadline {
    if isBusy {
      let steps = displayedSteps
      let done = steps.filter { $0.state == .done }.count
      return SyncHeadline(
        kind: .syncing, title: String(localized: .settings(.offlineSyncSyncing)),
        detail: steps.isEmpty
          ? nil : String(localized: .settings(.offlineSyncStepCount(done, steps.count))))
    }
    if store.libraryFilesPausedLowStorage {
      return SyncHeadline(
        kind: .paused, title: String(localized: .settings(.offlineSyncPausedLowStorage)))
    }
    if waitingForNetwork {
      return SyncHeadline(
        kind: .waiting, title: String(localized: .settings(.offlineSyncWaitingForWifi)))
    }
    if status?.lastRefreshedAt != nil, store.syncFailures.isEmpty, visibleSyncErrors.isEmpty {
      return SyncHeadline(
        kind: .upToDate, title: String(localized: .settings(.offlineSyncUpToDate)))
    }
    return SyncHeadline(kind: .idle, title: String(localized: .settings(.offlineSyncIdle)))
  }

  private func stepTitle(for stage: SyncActivity.Stage) -> String {
    switch stage {
    case .elementSync: String(localized: .settings(.offlineSyncStepElements))
    case .reconcile: String(localized: .settings(.offlineSyncStepReconcile))
    case .libraryFill: String(localized: .settings(.offlineSyncStepLists))
    case .detailFill: String(localized: .settings(.offlineSyncStepDetails))
    case .contentFill: String(localized: .settings(.offlineSyncStepText))
    case .fileDownload: String(localized: .settings(.offlineSyncStepFiles))
    }
  }

  /// What the running step is on: the saved view where it goes view by view,
  /// and the downloads' own figures.
  private func caption(for activity: SyncActivity) -> String? {
    if activity.stage == .fileDownload { return fileDownloadCaption }
    guard let part = activity.part else { return activity.detail }
    // A `nil` name is the default list.
    let name = activity.detail ?? String(localized: .settings(.offlineSyncDefaultView))
    // The reconcile has no count of its own there, so the position goes in
    // the count's place.
    guard activity.stage != .reconcile else { return name }
    return String(
      localized: .settings(.offlineSyncViewPosition(name, part.index + 1, part.count)))
  }

  private func countText(for activity: SyncActivity) -> String? {
    if let total = activity.total {
      let resource: LocalizedStringResource =
        switch activity.stage {
        // The reconcile counts changed documents, not documents overall.
        case .reconcile: .settings(.offlineSyncReconcileProgressCount(activity.completed, total))
        case .fileDownload: .settings(.offlineSyncFileProgressCount(activity.completed, total))
        case .libraryFill, .detailFill, .contentFill, .elementSync:
          .settings(.offlineSyncProgressCount(activity.completed, total))
        }
      return String(localized: resource)
    }
    if activity.stage == .reconcile, let part = activity.part {
      return String(localized: .settings(.offlineSyncViewCount(part.index + 1, part.count)))
    }
    return nil
  }

  /// The total, captioned with what it is made of, leading to the kept saved
  /// views where there are any. In both modes: a kept view outlasts a switch
  /// between them.
  @ViewBuilder
  private var keptOfflineRow: some View {
    let viewCount = store.keptOfflineViewIDs.count
    let ownCount = store.keptOfflineDocumentIDs.count
    if viewCount > 0 {
      Divider()
      CustomSectionRow {
        NavigationLink {
          KeptOfflineViewsView(status: status)
        } label: {
          HStack(spacing: 8) {
            keptOfflineSummary(views: viewCount, documents: ownCount)
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    } else if ownCount > 0 {
      Divider()
      CustomSectionRow { keptOfflineSummary(views: viewCount, documents: ownCount) }
    }
  }

  private func keptOfflineSummary(views: Int, documents: Int) -> some View {
    LabeledContent {
      Text(keptFilesText(keptOfflineFileProgress)).foregroundStyle(.secondary)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(.settings(.offlineSyncKeptOfflineHeader))
        Text(keptMembershipText(views: views, documents: documents))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// "1 saved view and 2 single documents", leaving out a kind with none.
  private func keptMembershipText(views: Int, documents: Int) -> String {
    var parts: [String] = []
    if views > 0 {
      parts.append(String(localized: .settings(.offlineSyncKeptOfflineSavedViewCount(views))))
    }
    if documents > 0 {
      parts.append(String(localized: .settings(.offlineSyncKeptOfflineSingleCount(documents))))
    }
    return parts.formatted(.list(type: .and))
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

  /// What the downloads cover: the whole library in *Entire library*, the
  /// kept documents otherwise, as the downloader scopes them.
  private var downloadProgress: LibraryFileProgress {
    mode == .entireLibrary
      ? libraryFileProgress : keptOfflineFileProgress
  }

  /// The download row counts from the file index, the same figure the rows
  /// below show once it's done, so the count doesn't jump when it goes.
  private func displayed(_ activity: SyncActivity) -> SyncActivity {
    guard activity.stage == .fileDownload else { return activity }
    var activity = activity
    activity.completed = downloadProgress.downloadedFiles
    activity.total = downloadProgress.totalDocuments
    return activity
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

  private var isDownloading: Bool {
    store.syncActivities.contains { $0.stage == .fileDownload }
  }

  /// The server's documents on the device; in *Entire library* also how many
  /// have their file, and whether the library has been cached in full. The
  /// file count is a caption so the value stays short enough to leave room
  /// for the label.
  private var documentsRow: some View {
    LabeledContent {
      Text(.settings(.offlineSyncDocumentsCached(status?.cachedDocumentCount ?? 0)))
        .foregroundStyle(.secondary)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(.settings(.offlineSyncDocuments))
        if mode == .entireLibrary {
          Group {
            Text(.settings(.offlineStorageFileCount(libraryFileProgress.downloadedFiles)))
            if status?.libraryCoverageAt == nil {
              Text(.settings(.offlineSyncLibraryIncomplete))
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
    }
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
}

/// The saved views kept offline, each with its figures, swiped to stop keeping
/// them.
private struct KeptOfflineViewsView: View {
  @Environment(DocumentStore.self) private var store
  @EnvironmentObject private var errorController: ErrorController

  let status: OfflineStatus?

  private var views: [(id: UInt, savedView: SavedView?)] {
    store.keptOfflineViewIDs
      .map { (id: $0, savedView: store.savedViews[$0]) }
      .sorted { ($0.savedView?.name ?? "") < ($1.savedView?.name ?? "") }
  }

  var body: some View {
    Form {
      Section {
        ForEach(views, id: \.id) { view in
          LabeledContent {
            Text(keptFilesText(status?.keptOfflineViewProgress[view.id] ?? .zero))
              .foregroundStyle(.secondary)
          } label: {
            Label(
              view.savedView?.name
                ?? String(localized: .settings(.offlineSyncKeptOfflineUnknownView)),
              systemImage: "arrow.down.circle.fill")
          }
          .swipeActions {
            Button(role: .destructive) {
              Task {
                do {
                  try await store.stopKeepingOffline(savedViewID: view.id)
                } catch {
                  errorController.push(error: error)
                }
              }
            } label: {
              Label(
                String(localized: .app(.stopKeepingSavedViewOffline)),
                systemImage: "arrow.down.circle")
            }
          }
        }
      } footer: {
        Text(.settings(.offlineSyncKeptOfflineFooter))
      }
      .labeledContentStyle(StatusRowStyle())
    }
    .navigationTitle(Text(.settings(.offlineSyncKeptOfflineHeader)))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private func keptFilesText(_ progress: LibraryFileProgress) -> String {
  String(
    localized: .settings(
      .offlineSyncKeptOfflineFiles(
        progress.downloadedFiles.formatted(), progress.totalDocuments.formatted(),
        byteText(progress.downloadedBytes))))
}

private func byteText(_ bytes: Int64) -> String {
  bytes.formatted(.byteCount(style: .file))
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
