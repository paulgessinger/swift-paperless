//
//  AppOverlays.swift
//  AppShared
//
//  App-wide notification surfaces:
//
//  - `swiftui-toasts` installed at root for all transient toasts.
//  - `errorOverlay` bridges `ErrorController` push events into toasts.
//  - `offlineToast` bridges `NetworkMonitor` online/offline *transitions*
//    into toasts — no persistent UI for the offline state, just a brief
//    announcement when the state flips.
//
//  The interactive `NeedsAuthBanner` is intentionally NOT installed here —
//  it lives in a `safeAreaInset` on the home document screen so existing
//  sheets visually hide it, preventing the user from triggering a SwiftUI
//  presentation conflict (only one modal per view at a time).
//

import SwiftUI
import Toasts

extension View {
  @MainActor
  public func appOverlays(
    errorController: ErrorController,
    networkMonitor: NetworkMonitor
  ) -> some View {
    self
      // The toast-bridge modifiers read `\.presentToast` from the
      // environment, so they must be wrapped by `installToast` — modifiers
      // see env values set by their parents, not by siblings/children
      // further out in the chain.
      .errorOverlay(errorController: errorController)
      .modifier(OfflineToastBridge(networkMonitor: networkMonitor))
      .installToast(position: .top)
  }
}
