//
//  ConnectionStatusBanner.swift
//  AppShared
//
//  Two pill-shaped status indicators for the active connection, intentionally
//  split by interactivity:
//
//  - `OfflineBanner` is purely informational ("you're offline"). It can live
//    in a `windowOverlay` UIWindow above all sheets/covers because there's
//    no action attached — nothing can conflict.
//  - `NeedsAuthBanner` has a tappable "Re-authenticate" action that presents
//    a SwiftUI sheet. SwiftUI permits only one presented modal per view, so
//    if a sheet is already up the cover/sheet can't appear. The pragmatic
//    fix: anchor this banner via `safeAreaInset` on the home document
//    screen so an existing sheet visually hides it — the user can't trigger
//    the conflicting presentation in the first place.
//
//  Offline takes priority — when the device is offline, re-auth would fail
//  anyway, so `NeedsAuthBanner` returns EmptyView in that state.
//

import Common
import SwiftUI

public struct OfflineBanner: View {
  @Environment(NetworkMonitor.self) private var networkMonitor

  public init() {}

  public var body: some View {
    Group {
      if !networkMonitor.isOnline {
        BannerContent(
          systemImage: "wifi.slash",
          tint: .secondary,
          label: Text(.app(.connectionStatusOfflineBanner)),
          action: nil
        )
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: networkMonitor.isOnline)
  }
}

public struct NeedsAuthBanner: View {
  @EnvironmentObject private var connectionManager: ConnectionManager
  @Environment(NetworkMonitor.self) private var networkMonitor

  public init() {}

  private var visibleId: UUID? {
    guard networkMonitor.isOnline,
      let id = connectionManager.activeConnectionId,
      connectionManager.needsAuth(for: id)
    else {
      return nil
    }
    return id
  }

  public var body: some View {
    Group {
      if let id = visibleId {
        BannerContent(
          systemImage: "lock.trianglebadge.exclamationmark",
          tint: .orange,
          label: Text(.app(.connectionStatusNeedsAuthBanner)),
          action: (
            Text(.app(.connectionStatusReauthAction)),
            { connectionManager.requestReauth(for: id) }
          )
        )
      }
    }
    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: networkMonitor.isOnline)
    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: connectionManager.needsAuthIds)
  }
}

private struct BannerContent: View {
  let systemImage: String
  let tint: Color
  let label: Text
  let action: (Text, () -> Void)?

  @Environment(\.colorScheme) private var colorScheme
  private var isDark: Bool { colorScheme == .dark }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
        .frame(width: 19, height: 19)
        .padding(.leading, 12)

      label
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .foregroundStyle(.primary)

      Spacer(minLength: 4)

      if let (actionLabel, run) = action {
        Button(action: run) {
          ZStack {
            Capsule()
              .fill(tint.opacity(isDark ? 0.22 : 0.14))
            actionLabel
              .foregroundStyle(tint)
              .padding(.horizontal, 12)
          }
          .frame(minWidth: 64)
          .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .padding([.top, .bottom, .trailing], 8)
      } else {
        Color.clear
          .frame(width: 12)
      }
    }
    .font(.system(size: 15, weight: .medium))
    .frame(minHeight: 48)
    .fixedSize(horizontal: false, vertical: true)
    .background {
      Capsule().fill(.thinMaterial)
    }
    .compositingGroup()
    .shadow(color: .black.opacity(isDark ? 0.0 : 0.12), radius: 16, y: 4)
    .padding(.horizontal, 8)
    .padding(.bottom, 4)
    .transition(
      .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .scale(scale: 0.85, anchor: .bottom)
          .combined(with: .opacity)
      )
    )
  }
}

#Preview("Offline") {
  VStack(spacing: 0) {
    Spacer()
    BannerContent(
      systemImage: "wifi.slash",
      tint: .secondary,
      label: Text(.app(.connectionStatusOfflineBanner)),
      action: nil)
  }
}

#Preview("Needs auth") {
  VStack(spacing: 0) {
    Spacer()
    BannerContent(
      systemImage: "lock.trianglebadge.exclamationmark",
      tint: .orange,
      label: Text(.app(.connectionStatusNeedsAuthBanner)),
      action: (Text(.app(.connectionStatusReauthAction)), {}))
  }
}
