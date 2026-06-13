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
  @ObservedObject private var appSettings = AppSettings.shared
  @Environment(DocumentStore.self) private var store
  @Environment(NetworkMonitor.self) private var networkMonitor
  @State private var stats = TransferStatistics.shared

  public init() {}

  private var unmetered: Bool {
    !networkMonitor.isExpensive && !networkMonitor.isConstrained
  }

  public var body: some View {
    Form {
      Section {
        Picker(selection: $appSettings.offlineBrowsingMode) {
          ForEach(AppSettings.OfflineBrowsingMode.allCases, id: \.self) { mode in
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
        if appSettings.offlineBrowsingMode == .entireLibrary {
          statusRow(
            String(localized: .settings(.offlineSyncLastFullFill)),
            value: dateText(store.libraryCoverageAt))
        }
        statusRow(
          String(localized: .settings(.offlineSyncLastRefresh)),
          value: dateText(store.lastReconcileAt))
      } header: {
        Text(.settings(.offlineSyncStatusHeader))
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
    .onChange(of: appSettings.offlineBrowsingMode) { _, mode in
      // Enabling "Entire library" kicks the proactive fill immediately (force,
      // bypassing the freshness marker); the unmetered gate still applies.
      guard mode == .entireLibrary else { return }
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
