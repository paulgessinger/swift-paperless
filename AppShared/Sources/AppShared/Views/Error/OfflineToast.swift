//
//  OfflineToast.swift
//  AppShared
//
//  Bridges NetworkMonitor's online/offline transitions to the swiftui-toasts
//  presentation system, in the same shape as ErrorDisplay. Replaces the
//  persistent offline pill — only the *transition* is announced; once the
//  toast auto-dismisses there's no remaining UI clutter.
//
//  Must be installed inside a parent that called `.installToast(...)`.
//

import SwiftUI
import Toasts

public struct OfflineToastBridge: ViewModifier {
  // Passed in explicitly: `.appOverlays(...)` is applied as the outermost
  // modifier on the app's body, so any `@Environment(NetworkMonitor.self)`
  // here would look up the value at a position *above* where
  // `.environment(networkMonitor)` sets it — the env modifier propagates
  // downward to descendants, not upward to ancestors.
  let networkMonitor: NetworkMonitor
  @Environment(\.presentToast) private var presentToast

  public init(networkMonitor: NetworkMonitor) {
    self.networkMonitor = networkMonitor
  }

  public func body(content: Content) -> some View {
    content
      .onChange(of: networkMonitor.isOnline) { _, newValue in
        if newValue {
          presentToast(
            ToastValue(
              icon: Image(systemName: "wifi")
                .foregroundStyle(.green),
              message: String(localized: .app(.connectionStatusBackOnlineToast)),
              duration: 3.0
            )
          )
        } else {
          presentToast(
            ToastValue(
              icon: Image(systemName: "wifi.slash")
                .foregroundStyle(.orange),
              message: String(localized: .app(.connectionStatusOfflinePillShort)),
              duration: 3.0
            )
          )
        }
      }
  }
}
