//
//  SyncRunsView.swift
//  swift-paperless
//
//  Debug-menu screen listing the recorded sync steps (`sync_run`), grouped
//  into runs. Debug-only: strings are verbatim English on purpose, so they
//  don't reach translators.
//

import AppShared
import Persistence
import SwiftUI
import UIKit

struct SyncRunsView: View {
  @Environment(ConnectionManager.self) private var connectionManager
  @Environment(DocumentStore.self) private var store

  private enum LoadState {
    case loading
    case loaded([SyncRunEntry])
    case unavailable
    case failed(String)
  }

  @State private var state = LoadState.loading
  @State private var confirmClear = false

  private func load() async {
    do {
      guard let entries = try await store.syncRuns() else {
        state = .unavailable
        return
      }
      state = .loaded(entries)
    } catch is CancellationError {
      // Left as it was: a cancelled refresh is not a failure.
    } catch {
      state = .failed(String(describing: error))
    }
  }

  private func clear() async {
    do {
      try await store.clearSyncRuns()
      await load()
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
          Text(verbatim: "Failed to read sync runs")
        }
      case .loaded(let entries):
        if entries.isEmpty {
          Text(verbatim: "No sync steps recorded yet.")
            .foregroundStyle(.secondary)
        }
        ForEach(entries) { step in
          StepRow(step: step, subject: subject(step))
        }
      }
    }
    .listStyle(.plain)
    .monospacedDigit()
    .navigationTitle(Text(verbatim: "Sync runs"))
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
      ToolbarItem(placement: .destructiveAction) {
        Button(role: .destructive) {
          confirmClear = true
        } label: {
          Label {
            Text(verbatim: "Clear")
          } icon: {
            Image(systemName: "trash")
          }
        }
      }
    }
    .confirmationDialog(
      Text(verbatim: "Delete every recorded sync step?"), isPresented: $confirmClear
    ) {
      Button(role: .destructive) {
        Task { await clear() }
      } label: {
        Text(verbatim: "Clear sync runs")
      }
    }
    .task { await load() }
    .refreshable { await load() }
  }

  // MARK: - Labels

  private func subject(_ step: SyncRunEntry) -> String {
    guard let id = step.serverID else {
      return step.step == "task" ? "background task" : "no server"
    }
    return connectionManager.connections[id]?.label ?? "Unknown server"
  }

  /// Local date and time to the second, without the zone offset.
  fileprivate static func timestamp(_ date: Date) -> String {
    date.formatted(
      Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .space, timeZone: .current)
        .year().month().day().time(includingFractionalSeconds: false))
  }

  fileprivate static func duration(from start: Date, to end: Date) -> String {
    let seconds = end.timeIntervalSince(start)
    if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
    if seconds < 60 { return String(format: "%.1f s", seconds) }
    return String(
      format: "%.0f min %.0f s", (seconds / 60).rounded(.down),
      seconds.truncatingRemainder(dividingBy: 60))
  }
}

/// One step: name, counts, duration and outcome, then when, trigger, server
/// and message.
private struct StepRow: View {
  let step: SyncRunEntry
  let subject: String

  private var outcome: String { step.outcome ?? "running" }

  private var outcomeColor: Color {
    switch step.outcome {
    case "ok": .green
    case "partial", "cancelled", "skipped": .orange
    case "failed", "interrupted": .red
    default: .secondary
    }
  }

  private var timing: String {
    guard let endedAt = step.endedAt else { return "" }
    return SyncRunsView.duration(from: step.startedAt, to: endedAt)
  }

  private var counts: String? {
    var parts: [String] = []
    if let succeeded = step.succeeded { parts.append("\(succeeded) ok") }
    if let failed = step.failed, failed > 0 { parts.append("\(failed) failed") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private var copyText: String {
    [
      "\(step.trigger) \(subject) \(step.step) \(outcome)",
      "started \(SyncRunsView.timestamp(step.startedAt))", timing, counts, step.message,
      "run \(step.runID.uuidString)", step.serverID.map { "server \($0.uuidString)" },
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 6) {
        Text(verbatim: step.step)
          .font(.subheadline)
        if let counts {
          Text(verbatim: counts)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text(verbatim: timing)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(verbatim: outcome)
          .font(.subheadline)
          .foregroundStyle(outcomeColor)
      }
      Text(verbatim: "\(SyncRunsView.timestamp(step.startedAt)) · \(step.trigger) · \(subject)")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let message = step.message {
        Text(verbatim: message)
          .font(.caption)
          .foregroundStyle(outcomeColor)
          .lineLimit(3)
      }
    }
    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    .contextMenu {
      Button {
        UIPasteboard.general.string = copyText
      } label: {
        Label {
          Text(verbatim: "Copy step")
        } icon: {
          Image(systemName: "doc.on.doc")
        }
      }
    }
  }
}

#Preview("Sync runs") {
  @Previewable @State var connectionManager = ConnectionManager(
    database: try! Database.inMemory())
  @Previewable @State var store = DocumentStore.preview()

  NavigationStack {
    SyncRunsView()
      .environment(connectionManager)
      .environment(store)
  }
}
