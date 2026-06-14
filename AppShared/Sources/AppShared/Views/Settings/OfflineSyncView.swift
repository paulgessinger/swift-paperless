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
            set: { connectionManager.setOfflineBrowsingMode($0) })
        ) {
          ForEach(OfflineBrowsingMode.allCases, id: \.self) { mode in
            Text(mode.localizedName).tag(mode)
          }
        } label: {
          Text(.settings(.offlineBrowsingModeLabel))
        }
      } header: {
        Text(.settings(.offlineBrowsingModeHeader))
      } footer: {
        Text(.settings(.offlineBrowsingModeDescription))
      }

      Section {
        statusRow(String(localized: .settings(.offlineSyncActivity)), value: activityText)
        if mode == .entireLibrary {
          statusRow(
            String(localized: .settings(.offlineSyncLastFullFill)),
            value: dateText(store.libraryCoverageAt))
        }
        statusRow(
          String(localized: .settings(.offlineSyncLastRefresh)),
          value: dateText(store.lastReconcileAt))

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
    if store.isFillingLibrary {
      String(localized: .settings(.offlineSyncFilling))
    } else if store.isRefreshing {
      String(localized: .settings(.offlineSyncRefreshing))
    } else {
      String(localized: .settings(.offlineSyncIdle))
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
