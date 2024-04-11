//
//  ConnectionsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.04.2024.
//

import os
import SwiftUI

struct ConnectionsView: View {
    @State private var extraHeaders: [ConnectionManager.HeaderValue] = []
    @ObservedObject private var connectionManager: ConnectionManager

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        _extraHeaders = State(initialValue: connectionManager.storedConnection?.extraHeaders ?? [])
    }

    var body: some View {
        if let stored = connectionManager.storedConnection {
            LabeledContent(String(localized: .settings.activeServerUrl), value: stored.url.absoluteString)
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

        } else {
            // @TODO: (multi-server) remove in a few versions
            Text(connectionManager.apiHost ?? "No server")
        }
    }
}
