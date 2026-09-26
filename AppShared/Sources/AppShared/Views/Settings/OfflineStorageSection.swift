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
        caption: documentsCaption)
      sizeRow(
        String(localized: .settings(.offlineStorageThumbnails)), bytes: usage?.thumbnails.bytes)
      sizeRow(String(localized: .settings(.offlineSyncTotal)), bytes: usage?.totalBytes)
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
      let measured = await store.storageUsage()
      // The detached scan ignores cancellation, so a superseded one can still
      // finish after the newer one; drop its result.
      guard !Task.isCancelled else { return }
      usage = measured
    }
  }

  /// The file count, plus the active server's share once another server has
  /// downloads too. The share belongs here rather than under Total: the
  /// database and thumbnails are shared and can't be split by server.
  private var documentsCaption: Text? {
    guard let usage else { return nil }
    let total = usage.content.total
    let files = String(localized: .settings(.offlineStorageFileCount(total.files)))
    guard let id = connectionManager.activeConnectionId else { return Text(files) }
    let thisServer = usage.content.byServer[id] ?? .zero
    // With just the one server the share would repeat the row's own figure.
    guard thisServer != total else { return Text(files) }
    return Text(
      .settings(
        .offlineStorageThisServer(files, thisServer.bytes.formatted(.byteCount(style: .file)))))
  }

  @ViewBuilder
  private func sizeRow(_ title: String, bytes: Int64?, caption: Text? = nil) -> some View {
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
      if let caption {
        caption
      }
    }
  }
}
