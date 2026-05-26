//
//  ConnectionStatusBanner.swift
//  AppShared
//
//  Unified status banner for the active connection. Observes both the
//  needs-auth flag on `ConnectionManager` and the `isOnline` flag on
//  `NetworkMonitor` and renders one of three states: offline, needs-auth,
//  or nothing. Offline takes priority — re-auth would fail anyway without
//  network.
//
//  Tap the needs-auth banner to ask `ConnectionManager` to present the
//  re-auth sheet (the app shell handles presentation, since the sheet is
//  built from app-target views).
//

import Common
import SwiftUI

public struct ConnectionStatusBanner: View {
  @EnvironmentObject private var connectionManager: ConnectionManager
  @Environment(NetworkMonitor.self) private var networkMonitor

  public init() {}

  private enum DisplayState {
    case offline
    case needsAuth(UUID)
    case none
  }

  private var displayState: DisplayState {
    if !networkMonitor.isOnline {
      return .offline
    }
    if let id = connectionManager.activeConnectionId,
      connectionManager.needsAuth(for: id)
    {
      return .needsAuth(id)
    }
    return .none
  }

  public var body: some View {
    Group {
      switch displayState {
      case .offline:
        offlineBanner
      case .needsAuth(let id):
        needsAuthBanner(connectionId: id)
      case .none:
        EmptyView()
      }
    }
    .animation(.spring(duration: 0.25), value: networkMonitor.isOnline)
    .animation(.spring(duration: 0.25), value: connectionManager.needsAuthIds)
  }

  private var offlineBanner: some View {
    BannerContent(
      systemImage: "wifi.slash",
      tint: .secondary,
      label: Text(.app(.connectionStatusOfflineBanner)),
      action: nil)
  }

  private func needsAuthBanner(connectionId: UUID) -> some View {
    BannerContent(
      systemImage: "lock.trianglebadge.exclamationmark",
      tint: .orange,
      label: Text(.app(.connectionStatusNeedsAuthBanner)),
      action: (
        Text(.app(.connectionStatusReauthAction)),
        {
          connectionManager.requestReauth(for: connectionId)
        }
      )
    )
  }
}

private struct BannerContent: View {
  let systemImage: String
  let tint: Color
  let label: Text
  let action: (Text, () -> Void)?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
      label
        .font(.footnote)
        .foregroundStyle(.primary)
      Spacer(minLength: 8)
      if let (actionLabel, run) = action {
        Button(action: run) {
          actionLabel
            .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.thinMaterial)
    .overlay(alignment: .bottom) {
      Divider()
    }
    .transition(.move(edge: .top).combined(with: .opacity))
  }
}

#Preview("Offline") {
  VStack(spacing: 0) {
    BannerContent(
      systemImage: "wifi.slash",
      tint: .secondary,
      label: Text(.app(.connectionStatusOfflineBanner)),
      action: nil)
    Rectangle().fill(.gray.opacity(0.1)).frame(height: 300)
  }
}

#Preview("Needs auth") {
  VStack(spacing: 0) {
    BannerContent(
      systemImage: "lock.trianglebadge.exclamationmark",
      tint: .orange,
      label: Text(.app(.connectionStatusNeedsAuthBanner)),
      action: (Text(.app(.connectionStatusReauthAction)), {}))
    Rectangle().fill(.gray.opacity(0.1)).frame(height: 300)
  }
}
