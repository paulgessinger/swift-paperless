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

private struct ConnectionSelectionViews: View {
  @ObservedObject var connectionManager: ConnectionManager
  let animated: Bool

  var body: some View {
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
        // Bit of a hack to have by-character line breaks
        let label = connectionManager.isServerUnique(conn.url) ? conn.shortLabel : conn.label
        Text(label.map { String($0) }.joined(separator: "\u{200B}"))
      }
      .disabled(conn.id == connectionManager.activeConnectionId)
    }
  }
}

struct ConnectionSelectionMenu: View {
  @ObservedObject var connectionManager: ConnectionManager
  let animated: Bool

  var body: some View {
    if let stored = connectionManager.storedConnection {
      Menu {
        ConnectionSelectionViews(connectionManager: connectionManager, animated: animated)
      } label: {
        HStack {
          let label =
            connectionManager.isServerUnique(stored.url) ? stored.shortLabel : stored.label
          Text(label)
            .font(.body)
            .foregroundStyle(.gray)
            .multilineTextAlignment(.leading)
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

struct ConnectionsView: View {
  @ObservedObject private var connectionManager: ConnectionManager
  @Binding var showLoginSheet: Bool

  @ScaledMetric(relativeTo: .title) private var plusIconSize = 18.0

  @State private var extraHeaders: [Connection.HeaderValue] = []

  @State private var logoutRequested = false

  @State private var backendVersion: Version?
  @State private var updateAvailable = false

  @State private var showExtraHeader = false

  @EnvironmentObject private var store: DocumentStore

  init(connectionManager: ConnectionManager, showLoginSheet: Binding<Bool>) {
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

  var body: some View {
    Section {
      if let stored = connectionManager.storedConnection {
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

        Button(role: .destructive) {
          logoutRequested = true
        } label: {
          Label(
            String(localized: .localizable(.logout)),
            systemImage: "rectangle.portrait.and.arrow.right")
        }
        .foregroundColor(Color.red)
        .bold()

        .confirmationDialog(
          String(localized: .localizable(.confirmationPromptTitle)), isPresented: $logoutRequested,
          titleVisibility: .visible
        ) {
          Button(String(localized: .localizable(.logout)), role: .destructive) {
            connectionManager.logout(animated: false)
          }
          Button(String(localized: .localizable(.cancel)), role: .cancel) {}
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
            .accessibilityLabel(Text(.localizable(.add)))
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

struct ConnectionQuickChangeMenu: View {
  @EnvironmentObject private var connectionManager: ConnectionManager

  var body: some View {
    if connectionManager.connections.count > 1 {
      Menu {
        ConnectionSelectionViews(connectionManager: connectionManager, animated: true)
      } label: {
        Label(localized: .settings(.activeServer), systemImage: "server.rack")
      }
    }
  }
}

private
  struct BackendVersionView: View
{

  let backendVersion: Version
  let updateAvailable: Bool

  private let releases = #URL("https://github.com/paperless-ngx/paperless-ngx/releases")

  var body: some View {
    LabeledContent {
      Text(backendVersion.description)
    } label: {
      Text(.settings(.backendVersion))
      if updateAvailable {
        Link(destination: releases) {
          HStack {
            Image(systemName: "arrow.up.circle.fill")
            Text(.settings(.updateAvailable))
          }
          .foregroundStyle(.green)
        }
      }
    }
  }
}

#Preview {
  Form {
    BackendVersionView(backendVersion: Version(1, 2, 3), updateAvailable: false)
    BackendVersionView(backendVersion: Version(1, 2, 3), updateAvailable: true)
  }
}
