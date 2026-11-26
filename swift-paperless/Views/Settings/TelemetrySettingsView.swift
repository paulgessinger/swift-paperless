import AppShared
import AppViews
import MarkdownUI
import Persistence
import SwiftUI

/// The opt-in toggle and a live view of the pings.
struct TelemetrySettingsView: View {
  /// Also the onboarding card's detail page, so both say the same thing.
  nonisolated static var explanation: String {
    String(localized: .telemetry(.explanation))
  }

  @Bindable private var appSettings = AppSettings.shared

  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager

  /// Both pings as the service would next send them.
  @State private var pings: [TelemetryUpcomingPing] = []

  private func loadPings() async {
    let environment = await TelemetryEnvironment.current(
      store: store, connectionManager: connectionManager)
    pings = TelemetryService.current.upcoming(environment: environment)
  }

  private func schedule(_ ping: TelemetryUpcomingPing) -> String {
    guard appSettings.telemetryOptIn == true else {
      return String(localized: .telemetry(.scheduleOff))
    }
    switch ping.nextSend {
    case .nextActivation:
      return String(localized: .telemetry(.scheduleNextOpen))
    case .notBefore(let date):
      let time = date.formatted(date: .abbreviated, time: .shortened)
      return ping.endpoint == .health
        ? String(localized: .telemetry(.scheduleHealthAfter(time)))
        : String(localized: .telemetry(.scheduleFeaturesAfter(time)))
    }
  }

  /// Matches the onboarding card, so the screen introduces itself the same way.
  private var header: some View {
    VStack(spacing: 12) {
      Image(systemName: "chart.bar")
        .font(.system(size: 30))
        .foregroundStyle(.tint)
        .frame(width: 60, height: 60)
        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityHidden(true)
      Text(.telemetry(.shareToggle))
        .font(.title2)
        .bold()
      Text(.telemetry(.summary))
        .foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
  }

  var body: some View {
    Form {
      Section {
        header
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
      }

      Section {
        Toggle(isOn: Binding($appSettings.telemetryOptIn, default: false)) {
          Text(.telemetry(.shareToggle))
        }
      } footer: {
        Text(.telemetry(.shareFooter))
      }

      Section {
        Markdown(Self.explanation)
      } header: {
        Text(.telemetry(.sharedHeader))
      }

      Section {
        DisclosureGroup {
          ForEach(pings, id: \.endpoint) { ping in
            VStack(alignment: .leading, spacing: 6) {
              Text(verbatim: "POST \(ping.endpoint.path)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
              if let day = ping.day {
                Text(.telemetry(.reportCovers(day)))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(verbatim: schedule(ping))
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(verbatim: String(decoding: ping.body, as: UTF8.self))
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
          }
        } label: {
          Text(.telemetry(.sentHeader))
        }
      } footer: {
        Text(.telemetry(.sentFooter))
      }
    }
    .task(id: appSettings.telemetryOptIn) {
      await loadPings()
    }
    .navigationTitle(Text(.telemetry(.title)))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  @Previewable @State var store = DocumentStore.preview()
  @Previewable @State var connectionManager = ConnectionManager(
    database: try! Database.inMemory())

  NavigationStack {
    TelemetrySettingsView()
      .environment(store)
      .environment(connectionManager)
  }
}
