//
//  AppOverlays.swift
//  AppShared
//
//  App-wide notification surfaces:
//
//  - Transient error toasts via `swiftui-toasts` (`.installToast` at root,
//    `errorOverlay` bridges from `ErrorController`).
//  - The non-interactive `OfflineBanner` in a `swiftui-window-overlay`
//    UIWindow at `.alert` level so it floats above any sheet/cover. Safe
//    because tapping it does nothing.
//
//  The interactive `NeedsAuthBanner` is intentionally NOT installed here —
//  it lives in a `safeAreaInset` on the home document screen so existing
//  sheets visually hide it, preventing the user from triggering a SwiftUI
//  presentation conflict (only one modal per view at a time).
//
//  Env objects are passed in explicitly because the UIKit-bridged overlay
//  windows used by swiftui-toasts and swiftui-window-overlay do not reliably
//  inherit `@EnvironmentObject` or `@Environment(Observable.self)` from the
//  enclosing view tree.
//

import SwiftUI
import Toasts
import WindowOverlay

private struct OfflineBannerOverlay: View {
  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      OfflineBanner()
    }
  }
}

extension View {
  @MainActor
  public func appOverlays(
    errorController: ErrorController,
    networkMonitor: NetworkMonitor
  ) -> some View {
    self
      .windowOverlay(isPresented: true) {
        OfflineBannerOverlay()
          .environment(networkMonitor)
      }
      // `errorOverlay` reads `\.presentToast` from the environment, so it
      // must be wrapped by `installToast` — modifiers see env values set by
      // their parents, not by siblings/children further out in the chain.
      .errorOverlay(errorController: errorController)
      .installToast(position: .top)
  }
}
