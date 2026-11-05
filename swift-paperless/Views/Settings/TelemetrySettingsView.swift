import AppShared
import AppViews
import SwiftUI

/// The text is a placeholder until telemetry exists, so it stays out of the
/// string catalogs.
struct TelemetrySettingsView: View {
  nonisolated static let title = "Anonymous usage"

  /// Also the onboarding card's detail page, so both say the same thing.
  nonisolated static let explanation = """
    Placeholder: the description of what is sent gets written with the \
    telemetry implementation.
    """

  @Bindable private var appSettings = AppSettings.shared

  var body: some View {
    Form {
      Section {
        Toggle(isOn: Binding($appSettings.telemetryOptIn, default: false)) {
          Text(verbatim: "Share anonymous usage")
        }
      } footer: {
        Text(verbatim: "Off unless you turn it on.")
      }

      Section {
        Text(verbatim: Self.explanation)
      } header: {
        Text(verbatim: "What's shared")
      }
    }
    .navigationTitle(Text(verbatim: Self.title))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    TelemetrySettingsView()
  }
}
