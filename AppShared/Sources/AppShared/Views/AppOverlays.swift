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
//  - `SchemaChangeEraseToastBridge` surfaces a DEBUG-only database erase
//    (see `Database.didEraseForSchemaChangeAtLaunch`) once, at launch.
//
//  None of this reaches the Share Extension: a toast renders into a
//  screen-level window, which the extension's sheet doesn't own. Its
//  counterpart is `ShareErrorBanner`.
//
//  The interactive `NeedsAuthBanner` is intentionally NOT installed here —
//  it lives in a `safeAreaInset` on the home document screen so existing
//  sheets visually hide it, preventing the user from triggering a SwiftUI
//  presentation conflict (only one modal per view at a time).
//

import Persistence
import SwiftUI
import Toasts

extension View {
  @MainActor
  public func appOverlays(
    errorController: ErrorController,
    networkMonitor: NetworkMonitor,
    database: Database
  ) -> some View {
    self
      // The toast-bridge modifiers read `\.presentToast` from the
      // environment, so they must be wrapped by `installToast` — modifiers
      // see env values set by their parents, not by siblings/children
      // further out in the chain.
      .errorOverlay(errorController: errorController)
      .modifier(OfflineToastBridge(networkMonitor: networkMonitor))
      .modifier(SchemaChangeEraseToastBridge(database: database))
      .installToast(position: .top)
  }
}
