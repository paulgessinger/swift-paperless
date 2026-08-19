//
//  OfflineSyncView.swift
//  swift-paperless
//
//  Central place to control and observe offline caching: the browsing-scope
//  setting, the current sync/fill status, and how much data the background
//  processes have moved (to inform Wi‑Fi gating).
//

import Networking
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

  public init() {}

  // The active server's mode, read/written through ConnectionManager (persisted
  // on the connection record). The setting is per-server.
  private var mode: OfflineBrowsingMode { connectionManager.activeOfflineBrowsingMode }

  private var unmetered: Bool {
    guard let networkMonitor else { return true }
    return !networkMonitor.isExpensive && !networkMonitor.isConstrained
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
                  Task { await store.fillLibraryIfEnabled(unmetered: unmetered, force: true) }
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
        Text(.settings(.offlineBrowsingModeDescription))
      }

      Section {
        statusRow(String(localized: .settings(.offlineSyncActivity)), value: activityText)
        if let activity = store.syncActivity {
          VStack(alignment: .leading, spacing: 4) {
            if let fraction = activity.fraction {
              ProgressView(value: fraction)
            } else {
              ProgressView().progressViewStyle(.linear)
            }
            HStack {
              if let detail = activity.detail {
                Text(detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              if let total = activity.total {
                Text(.settings(.offlineSyncProgressCount(activity.completed, total)))
                  .font(.caption)
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        if mode == .entireLibrary {
          statusRow(
            String(localized: .settings(.offlineSyncLastFullFill)),
            value: dateText(store.libraryCoverageAt))
        }
        statusRow(
          String(localized: .settings(.offlineSyncLastRefresh)),
          value: dateText(store.lastReconcileAt))
        statusRow(
          String(localized: .settings(.offlineSyncCachedDocuments)),
          value: store.cachedDocumentCount.formatted())

        Button {
          Task {
            // Explicit user action: bypass the reconcile throttle and the
            // unmetered gate, and force a re-fill ignoring the freshness marker.
            //
            // `userInitiated` exists precisely so this rethrows instead of
            // failing soft into `lastSyncError`; swallowing it here left a
            // "Sync now" that looked identical whether it worked or not.
            do {
              try await store.sync(userInitiated: true)
            } catch {
              errorController.push(error: error)
            }
            await store.fillLibraryIfEnabled(unmetered: true, force: true)
            // Both lifecycle paths pair the library fill with the detail fill;
            // without this, notes and file metadata could only ever be filled by
            // backgrounding and foregrounding the app.
            await store.fillDocumentDetailsIfEnabled(unmetered: true)
          }
        } label: {
          Label(String(localized: .settings(.offlineSyncNow)), systemImage: "arrow.clockwise")
        }
        .disabled(store.isFillingLibrary || store.isRefreshing)
      } header: {
        Text(.settings(.offlineSyncStatusHeader))
      }

      if mode == .entireLibrary, !store.syncErrors.isEmpty {
        Section {
          ForEach(store.syncErrors) { error in
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
        Text(.settings(.offlineSyncDataHeader))
      } footer: {
        Text(.settings(.offlineSyncDataSince(formattedDate(stats.since))))
      }
    }
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

  private var activityText: String {
    switch store.syncActivity?.stage {
    case .libraryFill: String(localized: .settings(.offlineSyncFilling))
    case .detailFill: String(localized: .settings(.offlineSyncDetailFill))
    case .reconcile: String(localized: .settings(.offlineSyncReconciling))
    case .elementSync: String(localized: .settings(.offlineSyncRefreshing))
    case nil:
      store.isRefreshing
        ? String(localized: .settings(.offlineSyncRefreshing))
        : String(localized: .settings(.offlineSyncIdle))
    }
  }

  private func dateText(_ date: Date?) -> String {
    guard let date else { return String(localized: .settings(.offlineSyncNever)) }
    return date.formatted(.relative(presentation: .named))
  }

  private func formattedDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }

  private func byteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
