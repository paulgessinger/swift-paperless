//
//  OfflineToast.swift
//  AppShared
//
//  Bridges NetworkMonitor's online/offline transitions to the swiftui-toasts
//  presentation system, in the same shape as ErrorDisplay. Replaces the
//  persistent offline pill — only the *transition* is announced; once the
//  toast auto-dismisses there's no remaining UI clutter.
//
//  The transition isn't the only trigger: `ErrorController.offlineNotices`
//  re-shows the same indicator at the moment a user-initiated read is blocked
//  by being offline (see `UserInitiatedErrors.swift`). That's what keeps the
//  premise of the suppression policy true for the *whole* offline session
//  rather than the few seconds after the link drops — feedback appears when
//  the user actually does something, instead of as chrome nobody reads.
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
  @ObservedObject var errorController: ErrorController

  @Environment(\.presentToast) private var presentToast

  // When the toast currently on screen goes away, as far as we know.
  @State private var offlineToastVisibleUntil: Date?

  private static let duration: TimeInterval = 3.0

  public init(networkMonitor: NetworkMonitor, errorController: ErrorController) {
    self.networkMonitor = networkMonitor
    self.errorController = errorController
  }

  /// Show the offline indicator, replacing rather than stacking: repeated
  /// pull-to-refreshes while offline keep showing one "Offline", not a column
  /// of them. The library hands back no dismiss handle, so "replace" is
  /// implemented as "don't queue a second one behind the one already up".
  private func presentOfflineToast() {
    let now = Date()
    if let until = offlineToastVisibleUntil, now < until { return }
    offlineToastVisibleUntil = now.addingTimeInterval(Self.duration)
    presentToast(
      ToastValue(
        icon: Image(systemName: "wifi.slash")
          .foregroundStyle(.orange),
        message: String(localized: .app(.connectionStatusOfflinePillShort)),
        duration: Self.duration
      )
    )
  }

  public func body(content: Content) -> some View {
    content
      .onChange(of: networkMonitor.isOnline) { _, newValue in
        if newValue {
          offlineToastVisibleUntil = nil
          presentToast(
            ToastValue(
              icon: Image(systemName: "wifi")
                .foregroundStyle(.green),
              message: String(localized: .app(.connectionStatusBackOnlineToast)),
              duration: Self.duration
            )
          )
        } else {
          presentOfflineToast()
        }
      }
      .onReceive(errorController.offlineNotices) { _ in
        presentOfflineToast()
      }
  }
}
