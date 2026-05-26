//
//  ConnectionsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.04.2024.
//

import Common
import Networking
import SwiftUI
import os

extension StoredConnection {
  fileprivate var nonEmptyFriendlyName: String? {
    guard let friendlyName, !friendlyName.isEmpty else { return nil }
    return friendlyName
  }
}

private struct ConnectionSelectionViews: View {
  @ObservedObject public var connectionManager: ConnectionManager
  public let animated: Bool

  public var body: some View {
    ForEach(
      connectionManager.connections.values.sorted(by: {
        $0.url.absoluteString < $1.url.absoluteString
      })
    ) { conn in
      Button {
        connectionManager.setActiveConnection(
          id: conn.id,
          animated: animated)
      } label: {
        let urlLabel = connectionManager.isServerUnique(conn.url) ? conn.shortLabel : conn.label
        let text = conn.nonEmptyFriendlyName.map { "\($0) (\(urlLabel))" } ?? urlLabel
        HStack {
          // Bit of a hack to have by-character line breaks
          Text(text.map { String($0) }.joined(separator: "\u{200B}"))
          if connectionManager.needsAuth(for: conn.id) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
              .foregroundStyle(.orange)
          }
        }
      }
      .disabled(conn.id == connectionManager.activeConnectionId)
    }
  }
}

public struct ConnectionSelectionMenu: View {
  @ObservedObject public var connectionManager: ConnectionManager
  public let animated: Bool

  public var body: some View {
    if let stored = connectionManager.storedConnection {
      Menu {
        ConnectionSelectionViews(connectionManager: connectionManager, animated: animated)
      } label: {
        let urlLabel =
          connectionManager.isServerUnique(stored.url) ? stored.shortLabel : stored.label
        HStack {
          if let friendlyName = stored.nonEmptyFriendlyName {
            VStack(alignment: .leading, spacing: 0) {
              Text(friendlyName)
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.leading)
              Text(urlLabel)
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.leading)
            }
          } else {
            Text(urlLabel)
              .font(.body)
              .foregroundStyle(.gray)
              .multilineTextAlignment(.leading)
          }
          Label(
            String(localized: .settings(.chooseServerAccessibilityLabel)),
            systemImage: "chevron.up.chevron.down"
          )
          .labelStyle(.iconOnly)
          .foregroundStyle(.gray)
        }
      }
    }
  }
}

public struct ConnectionsView: View {
  @ObservedObject private var connectionManager: ConnectionManager
  @Binding public var showLoginSheet: Bool

  @ScaledMetric(relativeTo: .title) private var plusIconSize = 18.0

  @State private var extraHeaders: [Connection.HeaderValue] = []

  @State private var logoutRequested = false

  @State private var backendVersion: Version?
  @State private var updateAvailable = false

  @State private var showExtraHeader = false

  @EnvironmentObject private var store: DocumentStore

  public init(connectionManager: ConnectionManager, showLoginSheet: Binding<Bool>) {
    self.connectionManager = connectionManager
    _extraHeaders = State(initialValue: connectionManager.storedConnection?.extraHeaders ?? [])
    _showLoginSheet = showLoginSheet
  }

  private func updateExtraHeaders() {
    Logger.shared.trace("Extra header manipulated in ConnectionsView")
    let existing = connectionManager.connection?.extraHeaders ?? []
    if existing != extraHeaders {
      Logger.shared.info("Active connection extra headers have changed")
      connectionManager.setExtraHeaders(extraHeaders)
      if let connection = connectionManager.connection {
        Task {
          let repository = await ApiRepository(
            connection: connection, mode: Bundle.main.appConfiguration.mode)
          store.set(repository: repository)
        }
      }
    }
  }

  public var body: some View {
    Section {
      if let stored = connectionManager.storedConnection {
        if let friendlyName = stored.nonEmptyFriendlyName {
          LabeledContent(.settings(.serverName), value: friendlyName)
        }

        HStack {
          Text(.settings(.activeServerUrl))
          Menu {
            ConnectionSelectionViews(
              connectionManager: connectionManager,
              animated: false)
          } label: {
            Text(stored.url.absoluteString)
              .font(.body)
              .foregroundStyle(.gray)
              .frame(maxWidth: .infinity, alignment: .trailing)

            Label(
              String(localized: .settings(.chooseServerAccessibilityLabel)),
              systemImage: "chevron.up.chevron.down"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(.gray)
          }
        }

        .sheet(isPresented: $showExtraHeader, onDismiss: updateExtraHeaders) {
          NavigationStack {
            ExtraHeadersView(headers: $extraHeaders)
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                  SaveButton {
                    showExtraHeader = false
                  }
                }
              }
          }
        }

        if let backendVersion {
          BackendVersionView(backendVersion: backendVersion, updateAvailable: updateAvailable)
        }

        LabeledContent(.settings(.activeServerUsername), value: stored.user.username)

        LabeledContent(
          .settings(.activeIdentity),
          value: stored.identity ?? String(localized: .login(.noIdentity)))

        NavigationLink {
          PermissionsView(userPermissions: store.permissions)
        } label: {
          Label(localized: .permissions(.title), systemImage: "lock.fill")
        }

        Button(.login(.extraHeaders), systemImage: "list.bullet.rectangle.fill") {
          showExtraHeader = true
        }
        .tint(.primary)

        if let activeId = connectionManager.activeConnectionId,
          connectionManager.needsAuth(for: activeId)
        {
          Button {
            connectionManager.requestReauth(for: activeId)
          } label: {
            Label(
              String(localized: .app(.connectionStatusReauthAction)),
              systemImage: "lock.trianglebadge.exclamationmark")
          }
          .foregroundStyle(.orange)
          .bold()
        }

        Button(role: .destructive) {
          logoutRequested = true
        } label: {
          Label(
            String(localized: .app(.logout)),
            systemImage: "rectangle.portrait.and.arrow.right")
        }
        .foregroundColor(Color.red)
        .bold()

        .confirmationDialog(
          String(localized: .app(.confirmationPromptTitle)), isPresented: $logoutRequested,
          titleVisibility: .visible
        ) {
          Button(String(localized: .app(.logout)), role: .destructive) {
            connectionManager.logout(animated: false)
          }
          Button(String(localized: .app(.cancel)), role: .cancel) {}
        }

      } else if let compat = connectionManager.connection {
        // @TODO: (multi-server) remove in a few versions
        Text(compat.url.absoluteString)
      }
    } header: {
      HStack {
        Text(.settings(.activeServer))
        Spacer()
        Button {
          showLoginSheet = true
        } label: {
          Image(systemName: "plus.circle").resizable()
            .frame(width: plusIconSize, height: plusIconSize)
            .accessibilityLabel(Text(.app(.add)))
        }
        .buttonStyle(BorderlessButtonStyle())
      }
    } footer: {
      if let backendVersion, backendVersion < ApiRepository.minimumVersion {
        Text(
          .settings(
            .unsupportedVersion(
              backendVersion.description, ApiRepository.minimumVersion.description)))
      }
    }

    .navigationBarTitleDisplayMode(.inline)

    .task {
      if let stored = connectionManager.storedConnection {
        do {
          let repository = try await ApiRepository(
            connection: stored.connection, mode: Bundle.main.appConfiguration.mode)
          backendVersion = repository.backendVersion
          updateAvailable = try await repository.remoteVersion().updateAvailable
        } catch {
          Logger.shared.error("Could not make ApiRepository for settings display: \(error)")
        }
      }
    }
  }
}

public struct ConnectionQuickChangeMenu: View {
  public init() {}

  @EnvironmentObject private var connectionManager: ConnectionManager

  public var body: some View {
    if connectionManager.connections.count > 1 {
      Menu {
        ConnectionSelectionViews(connectionManager: connectionManager, animated: true)
      } label: {
        Label(localized: .settings(.activeServer), systemImage: "server.rack")
      }
    }
  }
}

private struct BackendVersionView: View {

  public let backendVersion: Version
  public let updateAvailable: Bool?

  private let releases = #URL("https://github.com/paperless-ngx/paperless-ngx/releases")

  public var body: some View {
    LabeledContent {
      Text(backendVersion.description)
    } label: {
      Text(.settings(.backendVersion))
      if let updateAvailable {
        if updateAvailable {
          Link(destination: releases) {
            HStack {
              Image(systemName: "arrow.up.circle.fill")
              Text(.settings(.updateAvailable))
            }
          }
          .foregroundStyle(.green)
        } else {
          Text(.settings(.noUpdateAvailable))
        }
      } else {
        HStack {
          ProgressView()
          Text(.settings(.checkingVersion))
        }
      }
    }
    .animation(.default, value: updateAvailable)
  }
}

#Preview {
  @Previewable @State var updateAvailable: Bool? = nil

  Form {
    BackendVersionView(backendVersion: Version(1, 2, 3), updateAvailable: nil)
    BackendVersionView(backendVersion: Version(1, 2, 3), updateAvailable: false)
    BackendVersionView(backendVersion: Version(1, 2, 3), updateAvailable: updateAvailable)
    BackendVersionView(backendVersion: Version(1, 2, 3), updateAvailable: true)
  }

  .task {
    try? await Task.sleep(for: .seconds(1))
    updateAvailable = true
  }
}
