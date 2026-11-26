import AppShared
import AppViews
import SwiftUI

private struct TipJarLinks: ViewModifier {
  @State private var showTipJar = false
  /// The handler outside this view, which gets every other link.
  @Environment(\.openURL) private var openOtherURL

  func body(content: Content) -> some View {
    content
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard AppFeatures.enabled(.tipJar), TipJarLink.matches(url) else {
            openOtherURL(url)
            return .handled
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
  /// anywhere in this view; other links go to the enclosing `openURL` handler.
  /// Needs to sit inside any cover or sheet showing the links, because a view
  /// that is already presenting can't present the tip jar.
  func tipJarLinks() -> some View {
    modifier(TipJarLinks())
  }
}
