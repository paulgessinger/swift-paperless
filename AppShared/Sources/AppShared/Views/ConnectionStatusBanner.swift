//
//  ConnectionStatusBanner.swift
//  AppShared
//
//  Pill-shaped indicator for "the active connection needs re-authentication."
//  Has a tappable "Re-authenticate" action that presents a SwiftUI sheet.
//  Since SwiftUI permits only one presented modal per view, the banner is
//  anchored via `safeAreaInset` on the home document screen so any existing
//  sheet visually hides it — the user can't trigger a conflicting
//  presentation in the first place.
//
//  The companion offline state is announced as a transient toast by
//  `OfflineToastBridge` — no persistent surface there. While offline,
//  `NeedsAuthBanner` returns EmptyView (re-auth would fail anyway).
//

import Common
import SwiftUI

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
