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
  @Environment(NetworkMonitor.self) private var networkMonitor
  @State private var stats = TransferStatistics.shared
  @State private var downgradeRequested = false

  public init() {}

  // The active server's mode, read/written through ConnectionManager (persisted
  // on the connection record). The setting is per-server.
  private var mode: OfflineBrowsingMode { connectionManager.activeOfflineBrowsingMode }

  private var unmetered: Bool {
    !networkMonitor.isExpensive && !networkMonitor.isConstrained
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
          value: "\(store.cachedDocumentCount)")

        Button {
          Task {
            // Explicit user action: bypass the reconcile throttle and the
            // unmetered gate, and force a re-fill ignoring the freshness marker.
            try? await store.sync(userInitiated: true)
            await store.fillLibraryIfEnabled(unmetered: true, force: true)
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
    .onChange(of: mode) { old, new in
      // A genuine user switch *into* Entire library kicks an immediate (forced)
      // fill; the unmetered gate still applies.
      guard new == .entireLibrary, old != .entireLibrary else { return }
      Task { await store.fillLibraryIfEnabled(unmetered: unmetered, force: true) }
    }
  }

  @ViewBuilder
  private func statusRow(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
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
