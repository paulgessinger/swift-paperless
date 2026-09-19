//
//  OfflineStorageSection.swift
//  swift-paperless
//
//  Read-only statistics on how much disk the offline data takes: the database,
//  downloaded document files and thumbnails. Its own view so the Offline & Sync
//  screen only has to place it.
//

import Common
import SwiftUI

struct OfflineStorageSection: View {
  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager

  /// `nil` until the first measurement lands; the rows show a spinner rather
  /// than a misleading "Zero KB" meanwhile.
  @State private var usage: OfflineStorageUsage?

  var body: some View {
    Section {
      sizeRow(String(localized: .settings(.offlineStorageDatabase)), bytes: usage?.database.bytes)
      sizeRow(
        String(localized: .settings(.offlineStorageDocuments)), bytes: usage?.content.total.bytes,
        files: usage?.content.total.files)
      sizeRow(
        String(localized: .settings(.offlineStorageThumbnails)), bytes: usage?.thumbnails.bytes)
      sizeRow(String(localized: .settings(.offlineSyncTotal)), bytes: usage?.totalBytes)
      // Only worth a row once another server has downloads too; with just the
      // one it would repeat the row above.
      if let thisServer = activeServerContent, let usage, thisServer != usage.content.total {
        sizeRow(
          String(localized: .settings(.offlineStorageThisServer)), bytes: thisServer.bytes,
          files: thisServer.files)
      }
    } header: {
      Text(.settings(.offlineStorageHeader))
    } footer: {
      Text(.settings(.offlineStorageFooter))
    }
    // Measure on appear, and again whenever a sync starts or finishes, so a
    // "Sync now" or fill run on this screen shows its effect without leaving
    // and coming back. Not on every progress tick: the walk covers every
    // downloaded file, so it's too heavy to repeat per document.
    //
    // Every server, not just the active one: these rows are the all-servers
    // total, and a background sweep of an inactive server grows the same
    // database and the same blob store. Gating on `store.isSyncing` left the
    // figures stale until the active server happened to sync.
    .task(id: store.isAnyServerSyncing) {
      usage = await store.storageUsage()
    }
  }

  private var activeServerContent: DiskUsage? {
    guard let usage, let id = connectionManager.activeConnectionId else { return nil }
    return usage.content.byServer[id] ?? .zero
  }

  @ViewBuilder
  private func sizeRow(_ title: String, bytes: Int64?, files: Int? = nil) -> some View {
    // `LabeledContent` like the other status rows on this screen; a second
    // `Text` in the label renders as its subtitle.
    LabeledContent {
      if let bytes {
        Text(bytes.formatted(.byteCount(style: .file)))
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
      }
    } label: {
      Text(title)
      if let files {
        Text(.settings(.offlineStorageFileCount(files)))
      }
    }
  }
}
