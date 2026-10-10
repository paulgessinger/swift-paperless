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
    case loaded([Run])
    case unavailable
    case failed(String)
  }

  /// The steps of one run, newest step first.
  private struct Run: Identifiable {
    let id: UUID
    let steps: [SyncRunEntry]

    var first: SyncRunEntry { steps.last! }
    var startedAt: Date { steps.map(\.startedAt).min() ?? first.startedAt }
    /// `nil` while a step is still open.
    var endedAt: Date? {
      steps.contains(where: \.isOpen) ? nil : steps.compactMap(\.endedAt).max()
    }
  }

  @State private var state = LoadState.loading
  @State private var confirmClear = false

  private func load() async {
    do {
      guard let entries = try await store.syncRuns() else {
        state = .unavailable
        return
      }
      state = .loaded(Self.group(entries))
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

  /// Runs in the order of their newest step; entries arrive newest first.
  private static func group(_ entries: [SyncRunEntry]) -> [Run] {
    var order: [UUID] = []
    var steps: [UUID: [SyncRunEntry]] = [:]
    for entry in entries {
      if steps[entry.runID] == nil { order.append(entry.runID) }
      steps[entry.runID, default: []].append(entry)
    }
    return order.map { Run(id: $0, steps: steps[$0] ?? []) }
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
      case .loaded(let runs):
        if runs.isEmpty {
          Text(verbatim: "No sync steps recorded yet.")
            .foregroundStyle(.secondary)
        }
        ForEach(runs) { run in
          Section {
            ForEach(run.steps) { step in
              StepRow(step: step)
            }
          } header: {
            Text(verbatim: header(run))
          }
        }
      }
    }
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

  private func header(_ run: Run) -> String {
    let first = run.first
    let subject =
      first.serverID.map(serverTitle) ?? (first.step == "task" ? "background task" : "no server")
    let when = Self.timestamp(run.startedAt)
    let duration =
      run.endedAt.map { " · \(Self.duration(from: run.startedAt, to: $0))" } ?? " · running"
    return "\(first.trigger) · \(subject)\n\(when)\(duration)"
  }

  private func serverTitle(_ id: UUID) -> String {
    let label = connectionManager.connections[id]?.label ?? "Unknown server"
    return id == connectionManager.activeConnectionId ? "\(label) (active)" : label
  }

  fileprivate static func timestamp(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(timeZone: .current))
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

/// One step: its name and outcome, then timing, counts and message.
private struct StepRow: View {
  let step: SyncRunEntry

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
    var parts = ["started \(SyncRunsView.timestamp(step.startedAt))"]
    if let endedAt = step.endedAt {
      parts.append("took \(SyncRunsView.duration(from: step.startedAt, to: endedAt))")
    }
    return parts.joined(separator: " · ")
  }

  private var counts: String? {
    var parts: [String] = []
    if let succeeded = step.succeeded { parts.append("succeeded \(succeeded)") }
    if let failed = step.failed { parts.append("failed \(failed)") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private var copyText: String {
    [
      "\(step.trigger) \(step.step) \(outcome)", timing, counts, step.message,
      "run \(step.runID.uuidString)", step.serverID.map { "server \($0.uuidString)" },
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(verbatim: step.step)
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(verbatim: outcome)
          .font(.subheadline)
          .foregroundStyle(outcomeColor)
      }
      Group {
        Text(verbatim: timing)
        if let counts {
          Text(verbatim: counts)
        }
        if let message = step.message {
          Text(verbatim: message)
            .foregroundStyle(outcomeColor)
            .lineLimit(4)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
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
