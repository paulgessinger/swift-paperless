//
//  OfflineStorageSection.swift
//  swift-paperless
//
//  Read-only statistics on how much disk the offline data takes: the database,
//  downloaded document files, their OCR text and thumbnails. Its own view so the Offline & Sync
//  screen only has to place it.
//

import AppShared
import Common
import SwiftUI

struct OfflineStorageSection: View {
  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager

  /// `nil` until the first measurement lands; the rows show a spinner rather
  /// than a misleading "Zero KB" meanwhile.
  @State private var usage: OfflineStorageUsage?
  /// Bumped per measurement, so an older one that finishes late is dropped.
  @State private var generation = 0

  var body: some View {
    CustomSection {
      VStack(spacing: 0) {
        sizeRow(
          String(localized: .settings(.offlineStorageDatabase)), bytes: usage?.database.bytes,
          caption: searchIndexCaption)
        Divider()
        sizeRow(
          String(localized: .settings(.offlineStorageDocuments)),
          bytes: usage?.files.documents.bytes,
          caption: documentsCaption)
        Divider()
        sizeRow(String(localized: .settings(.offlineStorageText)), bytes: usage?.files.text.bytes)
        Divider()
        sizeRow(
          String(localized: .settings(.offlineStorageThumbnails)),
          bytes: usage?.files.thumbnails.bytes)
        Divider()
        sizeRow(String(localized: .settings(.offlineSyncTotal)), bytes: usage?.totalBytes)
      }
    } header: {
      Text(.settings(.offlineStorageHeader))
    } footer: {
      Text(.settings(.offlineStorageFooter))
    }
    // Measure on appear, and again whenever a sync starts or finishes, so a
    // "Sync now" or fill run on this screen shows its effect without leaving
    // and coming back. Not on every progress tick: the database is walked
    // each time, so it's too heavy to repeat per document.
    //
    // Every server, not just the active one: these rows are the all-servers
    // total, and a background sweep of an inactive server grows the same
    // database and the same blob store. Gating on `store.isSyncing` left the
    // figures stale until the active server happened to sync.
    // Re-measured when sync work starts or ends, and when the library's
    // downloads drain, which move the figures without any step running.
    .task(
      id: RefreshKey(syncing: store.isAnyServerSyncing, downloading: store.libraryFilesInFlight > 0)
    ) {
      await remeasure()
    }
    // And while on screen, whenever the file index grows or shrinks: a
    // document opened, thumbnails stored while scrolling, an eviction pass.
    // At most once a second; the stream keeps only the newest change.
    .task {
      guard let changes = store.fileIndexChanges() else { return }
      var first = true
      do {
        for try await _ in changes {
          // The stream's initial value; the task above measured already.
          if first {
            first = false
            continue
          }
          // The second runs alongside the scan, not after it.
          async let pause: Void = Task.sleep(for: .seconds(1))
          await remeasure()
          try await pause
        }
      } catch {}
    }
  }

  private func remeasure() async {
    generation += 1
    let current = generation
    let measured = await store.storageUsage()
    // The detached scan ignores cancellation, so a superseded one can still
    // finish after a newer one; drop its result.
    guard !Task.isCancelled, current == generation else { return }
    usage = measured
  }

  /// The file count, plus the active server's share once another server has
  /// downloads too. The share belongs here rather than under Total: the
  /// database and thumbnails are shared and can't be split by server.
  private var documentsCaption: Text? {
    guard let usage else { return nil }
    let total = usage.files.documents
    let files = String(localized: .settings(.offlineStorageFileCount(total.files)))
    guard let id = connectionManager.activeConnectionId else { return Text(files) }
    let thisServer = usage.files.documentsByServer[id] ?? .zero
    // With just the one server the share would repeat the row's own figure.
    guard thisServer != total else { return Text(files) }
    return Text(
      .settings(
        .offlineStorageThisServer(files, thisServer.bytes.formatted(.byteCount(style: .file)))))
  }

  /// What the full-text index takes of the database, once it holds anything:
  /// it is the part of that figure that grows with the downloaded texts.
  private var searchIndexCaption: Text? {
    guard let index = usage?.searchIndex, index.files > 0 else { return nil }
    return Text(
      .settings(
        .offlineStorageSearchIndex(index.bytes.formatted(.byteCount(style: .file)), index.files)))
  }

  @ViewBuilder
  private func sizeRow(_ title: String, bytes: Int64?, caption: Text? = nil) -> some View {
    CustomSectionRow {
      LabeledContent {
        if let bytes {
          Text(bytes.formatted(.byteCount(style: .file)))
            .foregroundStyle(.secondary)
        } else {
          ProgressView()
        }
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
          if let caption {
            caption
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

private struct RefreshKey: Equatable {
  let syncing: Bool
  let downloading: Bool
}
