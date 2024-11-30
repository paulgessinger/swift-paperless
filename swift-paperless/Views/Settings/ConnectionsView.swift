//
//  ConnectionsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.04.2024.
//

import Common
import os
import SwiftUI

struct ConnectionSelectionMenu: View {
    @ObservedObject var connectionManager: ConnectionManager

    var body: some View {
        ForEach(connectionManager.connections.values.sorted(by: { $0.url.absoluteString < $1.url.absoluteString })) { conn in
            Button {
                connectionManager.activeConnectionId = conn.id
            } label: {
                // Bit of a hack to have by-character line breaks
                let label = connectionManager.isServerUnique(conn.url) ? conn.shortLabel : conn.label
                Text(label.map { String($0) }.joined(separator: "\u{200B}"))
            }
            .disabled(conn.id == connectionManager.activeConnectionId)
        }
    }
}

struct ConnectionsView: View {
    @ObservedObject private var connectionManager: ConnectionManager
    @Binding var showLoginSheet: Bool

    @ScaledMetric(relativeTo: .title) private var plusIconSize = 18.0

    @State private var extraHeaders: [ConnectionManager.HeaderValue] = []

    @State private var logoutRequested = false

    @State private var backendVersion: Version?

    init(connectionManager: ConnectionManager, showLoginSheet: Binding<Bool>) {
        self.connectionManager = connectionManager
        _extraHeaders = State(initialValue: connectionManager.storedConnection?.extraHeaders ?? [])
        _showLoginSheet = showLoginSheet
    }

    var body: some View {
        Section {
            if let stored = connectionManager.storedConnection {
                HStack {
                    Text(.settings(.activeServerUrl))
                    Menu {
                        ConnectionSelectionMenu(connectionManager: connectionManager)
                    } label: {
                        Text(stored.url.absoluteString)
                            .font(.body)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Label(String(localized: .settings(.chooseServerAccessibilityLabel)),
                              systemImage: "chevron.up.chevron.down")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.gray)
                    }
                }

                LabeledContent(String(localized: .settings(.activeServerUsername)), value: stored.user.username)
                LabeledContent(String(localized: .settings(.activeIdentity)), value: stored.identity ?? String(localized: .login(.noIdentity)))
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Label(String(localized: .login(.extraHeaders)), systemImage: "list.bullet.rectangle.fill")
                }

                Button(role: .destructive) {
                    logoutRequested = true
                } label: {
                    Label(String(localized: .localizable(.logout)), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundColor(Color.red)
                .bold()

                .confirmationDialog(String(localized: .localizable(.confirmationPromptTitle)), isPresented: $logoutRequested, titleVisibility: .visible) {
                    Button(String(localized: .localizable(.logout)), role: .destructive) {
                        connectionManager.logout()
                    }
                    Button(String(localized: .localizable(.cancel)), role: .cancel) {}
                }

                .onChange(of: extraHeaders) {
                    Logger.shared.trace("Extra header manipulated in ConnectionsView")
                    connectionManager.setExtraHeaders(extraHeaders)
                }

            } else if let compat = connectionManager.connection {
                // @TODO: (multi-server) remove in a few versions
                Text(compat.url.absoluteString)
            }
        }
        header: {
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
        }
        footer: {
            if let backendVersion, backendVersion < ApiRepository.minimumVersion {
                Text(.settings(.unsupportedVersion(backendVersion.description, ApiRepository.minimumVersion.description)))
            }
        }

        .navigationBarTitleDisplayMode(.inline)

        .task {
            if let stored = connectionManager.storedConnection {
                do {
                    let repository = try await ApiRepository(connection: stored.connection)
                    backendVersion = await repository.backendVersion
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
                ConnectionSelectionMenu(connectionManager: connectionManager)
            } label: {
                Text(.settings(.activeServer))
            }
        }
    }
}
