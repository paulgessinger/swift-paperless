//
//  ConnectionsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.04.2024.
//

import os
import SwiftUI

private struct ConnectionSelectionMenu: View {
    @ObservedObject var connectionManager: ConnectionManager

    var body: some View {
        ForEach(connectionManager.connections.values.sorted(by: { $0.url.absoluteString < $1.url.absoluteString })) { conn in
            Button {
                withAnimation {
                    connectionManager.activeConnectionId = conn.id
                }
            } label: {
                // Bit of a hack to have by-character line breaks
                Text(conn.label.map { String($0) }.joined(separator: "\u{200B}"))
            }
            .disabled(conn.id == connectionManager.activeConnectionId)
        }
    }
}

struct ConnectionsView: View {
    @State private var extraHeaders: [ConnectionManager.HeaderValue] = []
    @ObservedObject private var connectionManager: ConnectionManager

    @ScaledMetric(relativeTo: .title) private var plusIconSize = 18.0

    @State private var showLoginScreen = false

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        _extraHeaders = State(initialValue: connectionManager.storedConnection?.extraHeaders ?? [])
    }

    var body: some View {
        Section {
            if let stored = connectionManager.storedConnection {
                HStack {
                    Text(.settings.activeServerUrl)
                    Menu {
                        ConnectionSelectionMenu(connectionManager: connectionManager)
                    } label: {
                        Text(stored.url.absoluteString)
                            .font(.body)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Label(String(localized: .settings.chooseServerAccessibilityLabel),
                              systemImage: "chevron.up.chevron.down")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.gray)
                    }
                }

                LabeledContent(String(localized: .settings.activeServerUsername), value: stored.user.username)

                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Label(String(localized: .login.extraHeaders), systemImage: "list.bullet.rectangle.fill")
                }

                .onChange(of: extraHeaders) { _ in
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
                Text(.settings.activeServer)
                Spacer()
                Button {
                    showLoginScreen = true
                } label: {
                    Image(systemName: "plus.circle").resizable()
                        .frame(width: plusIconSize, height: plusIconSize)
                        .accessibilityLabel(Text(.localizable.add))
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }

        .sheet(isPresented: $showLoginScreen) {
            // @TODO: Dismiss
            LoginView(connectionManager: connectionManager)
        }
    }
}

struct ConnectionQuickChangeMenu: View {
    @EnvironmentObject private var connectionManager: ConnectionManager

    var body: some View {
        if let stored = connectionManager.storedConnection {
            Menu {
                ConnectionSelectionMenu(connectionManager: connectionManager)
            } label: {
                Text(.settings.activeServer)
            }
        }
    }
}
