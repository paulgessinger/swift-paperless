import AppShared
import AppViews
import SwiftUI

private struct TipJarLinks: ViewModifier {
  @State private var showTipJar = false

  func body(content: Content) -> some View {
    content
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard AppFeatures.enabled(.tipJar), TipJarLink.matches(url) else {
            return .systemAction
          }
          showTipJar = true
          return .handled
        }
      )
      .sheet(isPresented: $showTipJar) {
        NavigationStack {
          TipJarView()
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button(.app(.ok)) { showTipJar = false }
              }
            }
        }
      }
  }
}

extension View {
  /// Opens the tip jar for ``TipJarLink`` instead of the browser, for links
  /// anywhere in this view. Needs to sit inside any cover or sheet showing the
  /// links, because a view that is already presenting can't present the tip jar.
  func tipJarLinks() -> some View {
    modifier(TipJarLinks())
  }
}
