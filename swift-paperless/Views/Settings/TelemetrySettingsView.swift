import AppShared
import AppViews
import MarkdownUI
import Persistence
import SwiftUI

/// The opt-in toggle and a live view of the pings. The text stays out of the
/// string catalogs until it is final.
struct TelemetrySettingsView: View {
  nonisolated static let title = "Anonymous usage"

  /// Also the onboarding card's detail page, so both say the same thing.
  nonisolated static let explanation = """
    Once a day, the app can send two short, separate reports to a server run \
    by the developer. They help decide what to build and fix, and when it's \
    safe to drop support for old versions.

    **Your setup**

    - App version, iOS version (such as 18), and iPhone or iPad
    - App language, without your region
    - Your server's Paperless-ngx version (such as 2.14.3)
    - Rough library size, and how you sign in
    - On how many days this month you opened the app, in ranges
    - Kinds of connection problems seen that day

    **Features you used**

    - Which features you used that day, and roughly how often: once, a few \
    times, or 10 or more

    **Never sent**

    - Your documents or any data from your server
    - Your server's address, your username, or anything you type
    - Any identifier for you or your device

    The server can't tell which reports came from the same device, and it \
    keeps only totals, never the reports themselves. Your IP address isn't \
    stored.

    [How this works](https://swift-paperless.app/usage/)
    """

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
      return "Not sent while sharing is off."
    }
    switch ping.nextSend {
    case .nextActivation:
      return "Sent the next time you open the app."
    case .notBefore(let date):
      let time = date.formatted(date: .abbreviated, time: .shortened)
      return ping.endpoint == .health
        ? "Sent today. Sent again the first time you open the app after \(time)."
        : "Still recording today. Sent the first time you open the app after \(time)."
    }
  }

  var body: some View {
    Form {
      Section {
        Toggle(isOn: Binding($appSettings.telemetryOptIn, default: false)) {
          Text(verbatim: "Share anonymous usage")
        }
      } footer: {
        Text(verbatim: "Off unless you turn it on. Nothing identifies you or your documents.")
      }

      Section {
        Markdown(Self.explanation)
      } header: {
        Text(verbatim: "What's shared")
      }

      Section {
        DisclosureGroup {
          ForEach(pings, id: \.endpoint) { ping in
            VStack(alignment: .leading, spacing: 6) {
              Text(verbatim: "POST \(ping.endpoint.path)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
              if let day = ping.day {
                Text(verbatim: "Covers \(day) (UTC)")
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
          Text(verbatim: "What's sent")
        }
      } footer: {
        Text(
          verbatim:
            "The exact reports this device would send, as things stand now. They can still change before they're sent, and the app sends only when you open it while connected to a server. Sending any report tells the server that an install of the app was used."
        )
      }
    }
    .task(id: appSettings.telemetryOptIn) {
      await loadPings()
    }
    .navigationTitle(Text(verbatim: Self.title))
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
