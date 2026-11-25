import AppShared
import SwiftUI

/// Everything telemetry keeps on the device and every feature payload it could
/// send. Debug menu only, so not localized.
struct TelemetryDebugView: View {
  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager

  @State private var snapshot: TelemetryDebugSnapshot?
  @State private var pings: [TelemetryUpcomingPing] = []

  private func load() async {
    let environment = await TelemetryEnvironment.current(
      store: store, connectionManager: connectionManager)
    snapshot = TelemetryService.current.debugSnapshot(environment: environment)
    pings = TelemetryService.current.upcoming(environment: environment)
  }

  var body: some View {
    Form {
      if let snapshot {
        stateSection(snapshot)
        pendingSection(snapshot)
        healthSection
        featureSection(snapshot)
      }
    }
    .task { await load() }
    .refreshable { await load() }
    .navigationTitle(Text(verbatim: "Telemetry state"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func stateSection(_ snapshot: TelemetryDebugSnapshot) -> some View {
    let state = snapshot.state
    return Section {
      row("Consented", snapshot.consented ? "yes" : "no")
      row("Now (UTC day)", TelemetryDay.string(for: snapshot.now))
      row("Health last sent", state.healthLastSent)
      row("Health last month", state.healthLastMonth)
      row("Health last week", state.healthLastWeek)
      row("Feature last reported", state.featureLastReported)
      row("Install stamp", state.installStamp?.storedValue)
      row("Active days", state.activeDays.sorted().joined(separator: ", "))
    } header: {
      Text(verbatim: "Stored state")
    }
  }

  private func pendingSection(_ snapshot: TelemetryDebugSnapshot) -> some View {
    Section {
      if snapshot.pendingByProcess.isEmpty {
        Text(verbatim: "Nothing pending")
          .foregroundStyle(.secondary)
      }
      ForEach(snapshot.pendingByProcess.keys.sorted(), id: \.self) { process in
        let pending = snapshot.pendingByProcess[process]!
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: process)
            .font(.caption.bold())
          Text(verbatim: describe(pending))
            .font(.caption.monospaced())
            .textSelection(.enabled)
        }
      }
    } header: {
      Text(verbatim: "Pending, per process")
    } footer: {
      Text(verbatim: "Exact counts as stored, before bucketing and pruning.")
    }
  }

  @ViewBuilder
  private var healthSection: some View {
    if let health = pings.first(where: { $0.endpoint == .health }) {
      Section {
        payload(String(decoding: health.body, as: UTF8.self))
      } header: {
        Text(verbatim: "POST /t/health")
      } footer: {
        Text(verbatim: describe(health.nextSend))
      }
    }
  }

  private func featureSection(_ snapshot: TelemetryDebugSnapshot) -> some View {
    Section {
      if snapshot.featureDays.isEmpty {
        Text(verbatim: "No reportable days")
          .foregroundStyle(.secondary)
      }
      ForEach(snapshot.featureDays) { day in
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: "\(day.day): \(describe(day.status))")
            .font(.caption.bold())
          payload(day.body)
        }
      }
    } header: {
      Text(verbatim: "POST /t/feature, per day")
    } footer: {
      Text(
        verbatim:
          "Only the latest completed day is reported; older unreported days are dropped."
      )
    }
  }

  private func row(_ label: String, _ value: String?) -> some View {
    LabeledContent {
      Text(verbatim: value.flatMap { $0.isEmpty ? nil : $0 } ?? "–")
        .font(.body.monospaced())
        .textSelection(.enabled)
    } label: {
      Text(verbatim: label)
    }
  }

  private func payload(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.caption.monospaced())
      .textSelection(.enabled)
  }

  private func describe(_ pending: TelemetryPending) -> String {
    let days = Set(pending.features.keys).union(pending.errors.keys).sorted(by: >)
    return days.map { day in
      let features = (pending.features[day] ?? [:])
        .map { "\($0.key.rawValue)=\($0.value)" }.sorted()
      let errors = (pending.errors[day] ?? []).map(\.rawValue).sorted()
      return "\(day): \((features + errors.map { "error:\($0)" }).joined(separator: ", "))"
    }.joined(separator: "\n")
  }

  private func describe(_ next: TelemetryNextSend) -> String {
    switch next {
    case .nextActivation:
      "Due: sent on the next activation."
    case .notBefore(let date):
      "Not due before \(date.formatted(date: .abbreviated, time: .shortened))."
    }
  }

  private func describe(_ status: TelemetryDebugSnapshot.FeatureDay.Status) -> String {
    switch status {
    case .today: "today, still recording"
    case .next: "reported next"
    case .skipped: "skipped"
    }
  }
}
