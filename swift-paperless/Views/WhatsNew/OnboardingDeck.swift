import AppShared
import SwiftUI

extension WhatsNewDeck {
  /// Bundled, because it shows before any server is connected. Its text goes
  /// through the string catalogs, unlike published decks.
  static var onboarding: WhatsNewDeck {
    let blocks: [Block] = [
      .card(
        Card(
          icon: "server.rack",
          title: String(localized: .login(.onboardingServerTitle)),
          text: String(localized: .login(.onboardingServerText)))),
      .card(
        Card(
          icon: "doc.viewfinder",
          title: String(localized: .login(.onboardingScanTitle)),
          text: String(localized: .login(.onboardingScanText)))),
      .card(
        Card(
          icon: "line.3.horizontal.decrease.circle",
          title: String(localized: .login(.onboardingFindTitle)),
          text: String(localized: .login(.onboardingFindText)))),
      .card(
        Card(
          icon: "lock.shield",
          title: String(localized: .login(.onboardingPrivacyTitle)),
          text: String(localized: .login(.onboardingPrivacyText)))),
      .telemetry(
        Card(
          icon: "chart.bar",
          title: "Share anonymous usage",
          text: "Optional, and off unless you turn it on.",
          detail:
            "Placeholder: the description of what is sent gets written with the telemetry implementation."
        )),
    ]

    return WhatsNewDeck(
      version: "onboarding",
      pages: [
        Page(
          title: String(localized: .login(.onboardingTitle)),
          subtitle: String(localized: .login(.onboardingSubtitle)),
          blocks: blocks)
      ])
  }
}

#Preview {
  WhatsNewDeckView(deck: .onboarding) {}
}
