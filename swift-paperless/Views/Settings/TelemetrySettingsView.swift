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

    [How this works](https://swift-paperless.app/telemetry/)
    """

  @Bindable private var appSettings = AppSettings.shared

  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager

  /// The pings as the service would send them now, by endpoint.
  @State private var payloads: [TelemetryEndpoint: String] = [:]

  private func loadPayloads() async {
    let environment = await TelemetryEnvironment.current(
      store: store, connectionManager: connectionManager)
    payloads = TelemetryService.current.preview(environment: environment)
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
          ForEach(TelemetryEndpoint.allCases, id: \.self) { endpoint in
            if let payload = payloads[endpoint] {
              VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "POST \(endpoint.path)")
                  .font(.caption.bold())
                  .foregroundStyle(.secondary)
                Text(verbatim: payload)
                  .font(.caption.monospaced())
                  .textSelection(.enabled)
              }
            }
          }
        } label: {
          Text(verbatim: "What's sent")
        }
      } footer: {
        Text(
          verbatim:
            "The exact reports this device would send now. The features report covers the last day you used the app and is shown only until it has been sent. Sending any report tells the server that an install of the app was used."
        )
      }
    }
    .task(id: appSettings.telemetryOptIn) {
      await loadPayloads()
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
