//
//  DatabaseStatisticsView.swift
//  swift-paperless
//
//  Debug-menu screen with the local database's row counts and sync
//  bookkeeping. Debug-only: strings are verbatim English on purpose, so they
//  don't reach translators.
//

import AppShared
import AppViews
import Common
import DataModel
import Persistence
import SwiftUI
import UIKit

struct DatabaseStatisticsView: View {
  @Environment(ConnectionManager.self) private var connectionManager
  @Environment(DocumentStore.self) private var store

  private enum LoadState {
    case loading
    case loaded(DatabaseStatistics)
    case unavailable
    case failed(String)
  }

  @State private var state = LoadState.loading

  private func load() async {
    do {
      state = try await store.databaseStatistics().map(LoadState.loaded) ?? .unavailable
    } catch is CancellationError {
      // Left as it was: a cancelled refresh is not a failure.
    } catch {
      state = .failed(String(describing: error))
    }
  }

  var body: some View {
    List {
      switch state {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity)
      case .unavailable:
        Text(verbatim: "No database: there is no active server session.")
      case .failed(let message):
        Section {
          Text(verbatim: message)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        } header: {
          Text(verbatim: "Failed to read statistics")
        }
      case .loaded(let stats):
        content(stats)
      }
    }
    .monospacedDigit()
    .navigationTitle(Text(verbatim: "Database"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task { await load() }
        } label: {
          Label {
            Text(verbatim: "Refresh")
          } icon: {
            Image(systemName: "arrow.clockwise")
          }
        }
      }
    }
    .task { await load() }
    .refreshable { await load() }
  }

  @ViewBuilder
  private func content(_ stats: DatabaseStatistics) -> some View {
    Section {
      row("Migrations", "\(stats.appliedMigrations.count) of \(stats.registeredMigrationCount)")
      row("Latest migration", stats.appliedMigrations.last ?? "none")
      if stats.didEraseForSchemaChangeAtLaunch {
        row("Erased at launch", "schema change")
      }
      row("SQLite", stats.sqliteVersion)
      row("Journal mode", stats.journalMode)
      row("Page size", bytes(Int64(stats.pageSize)))
      row("Pages", "\(stats.pageCount) (\(stats.freePageCount) free)")
      row("Main file", bytes(Int64(stats.pageCount) * Int64(stats.pageSize)))
      row("On disk incl. WAL", bytes(stats.diskUsageBytes))
      DisclosureGroup {
        ForEach(stats.appliedMigrations, id: \.self) { identifier in
          Text(verbatim: identifier)
            .font(.caption.monospaced())
        }
      } label: {
        Text(verbatim: "Applied migrations")
      }
    } header: {
      Text(verbatim: "Database")
    }

    Section {
      ForEach(stats.tables, id: \.name) { table in
        row(table.name, "\(table.rows)", monospacedLabel: true)
      }
    } header: {
      Text(verbatim: "Rows per table (all servers)")
    }

    ForEach(stats.servers) { server in
      serverSection(server)
      querySection(server)
    }
  }

  @ViewBuilder
  private func serverSection(_ server: DatabaseStatistics.Server) -> some View {
    Section {
      row("Server ID", server.id.uuidString)
      row("Offline browsing", server.offlineBrowsingMode)
      row("Sync over cellular", server.syncOverCellular ? "yes" : "no")
      row("Needs auth", server.needsAuth ? "yes" : "no")
      row("Delta watermark", timestamp(server.deltaWatermark))
      row("Library coverage", timestamp(server.libraryCoverageAt))
      row("Skeleton order rows", "\(server.skeletonRows)")
      row("Unreferenced documents", "\(server.unreferencedDocuments)")
      row("Awaiting notes", "\(server.documentsAwaitingNotes)")
      row("Awaiting file metadata", "\(server.documentsAwaitingFileMetadata)")
      DisclosureGroup {
        ForEach(server.rowsByTable.sorted { $0.key < $1.key }, id: \.key) { table, rows in
          row(table, "\(rows)", monospacedLabel: true)
        }
      } label: {
        Text(verbatim: "Rows per table")
      }
    } header: {
      Text(verbatim: serverTitle(server.id))
    }
  }

  @ViewBuilder
  private func querySection(_ server: DatabaseStatistics.Server) -> some View {
    let labels = queryLabels(serverID: server.id)
    Section {
      if server.queries.isEmpty {
        Text(verbatim: "None")
          .foregroundStyle(.secondary)
      }
      ForEach(server.queries) { query in
        QueryRow(query: query, label: labels[query.key], timestamp: timestamp)
      }
    } header: {
      Text(verbatim: "Cached lists: \(serverTitle(server.id))")
    } footer: {
      Text(
        verbatim: """
          rows: query_order rows, last: highest position, skel: rows without a \
          document, unplaced: rows with no placed_modified, gen/basis: the order \
          is stale while they differ.
          """)
    }
  }

  // MARK: - Labels

  private func serverTitle(_ id: UUID) -> String {
    let label = connectionManager.connections[id]?.label ?? "Unknown server"
    return id == connectionManager.activeConnectionId ? "\(label) (active)" : label
  }

  /// Names for the keys the app can derive: the default list for every server,
  /// and the saved views and restored filter for the active one, whose saved
  /// views are the only ones loaded.
  private func queryLabels(serverID: UUID) -> [QueryKey: String] {
    var labels: [QueryKey: String] = [:]
    if serverID == connectionManager.activeConnectionId {
      labels[QueryKey(serverID: serverID, filter: FilterModel.restoredFilterState())] =
        "Last used filter"
      for view in store.savedViews.values {
        labels[QueryKey(serverID: serverID, filter: FilterState(savedView: view))] =
          "Saved view: \(view.name)"
      }
    }
    // Last, so it wins when a saved view or the restored filter hashes the same.
    labels[QueryKey(serverID: serverID, filter: .default)] = "Default list"
    return labels
  }

  // MARK: - Formatting

  private func row(_ label: String, _ value: String, monospacedLabel: Bool = false) -> some View {
    LabeledContent {
      Text(verbatim: value)
        .textSelection(.enabled)
    } label: {
      Text(verbatim: label)
        .font(monospacedLabel ? .body.monospaced() : .body)
    }
  }

  private func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
  }

  private func timestamp(_ date: Date?) -> String {
    date?.formatted(Date.ISO8601FormatStyle(timeZone: .current)) ?? "never"
  }
}

/// One cached list: what identifies it, then its counters.
private struct QueryRow: View {
  let query: DatabaseStatistics.Query
  let label: String?
  let timestamp: (Date?) -> String

  private var counts: String {
    let total = query.totalCount.map(String.init) ?? "–"
    let last = query.lastPosition.map(String.init) ?? "–"
    return
      "total \(total) · rows \(query.orderRows) · last \(last) · skel \(query.skeletonRows) · unplaced \(query.unknownPlacementRows)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(verbatim: label ?? "Other list")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(verbatim: String(query.key.rawValue.prefix(12)))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      Group {
        Text(verbatim: counts)
        Text(verbatim: "filled \(timestamp(query.filledAt))")
        Text(verbatim: "viewed \(timestamp(query.viewedAt))")
        Text(
          verbatim:
            "gen \(query.orderGeneration) / basis \(query.orderBasis)\(query.orderStale ? " · stale" : "")"
        )
        .foregroundStyle(query.orderStale ? .orange : .secondary)
        if let error = query.syncError {
          Text(
            verbatim:
              "sync error \(timestamp(error.failedAt)) (\(error.savedViewName ?? "default list")): \(error.message)"
          )
          .foregroundStyle(.red)
          .lineLimit(3)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .contextMenu {
      Button {
        UIPasteboard.general.string = query.key.rawValue
      } label: {
        Label {
          Text(verbatim: "Copy query key")
        } icon: {
          Image(systemName: "doc.on.doc")
        }
      }
    }
  }
}

#Preview("Database statistics") {
  @Previewable @State var connectionManager = ConnectionManager(
    database: try! Database.inMemory())
  @Previewable @State var store = DocumentStore.preview()

  NavigationStack {
    DatabaseStatisticsView()
      .environment(connectionManager)
      .environment(store)
  }
}
