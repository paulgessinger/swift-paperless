//
//  ShareView.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 29.04.2024.
//

import os
import SwiftUI

struct ShareView: View {
    @ObservedObject var attachmentManager: AttachmentManager

    @StateObject private var connectionManager = ConnectionManager()

    @StateObject private var store = DocumentStore(repository: NullRepository())
    @StateObject private var errorController = ErrorController()

    @State private var error: String = ""
    @State private var showingError = false
    @State private var totalInputs = 0

    var callback: () -> Void

    init(attachmentManager: AttachmentManager, callback: @escaping () -> Void) {
        self.attachmentManager = attachmentManager
        self.callback = callback
    }

    private func internalCallback() {
        attachmentManager.importUrls.removeFirst()
        Logger.shared.info("Document created \(attachmentManager.importUrls) inputs left")
        if attachmentManager.importUrls.isEmpty {
            callback()
        }
    }

    private func refreshConnection() {
        Logger.api.info("Connection info changed, reloading!")

        if let conn = connectionManager.connection {
            Logger.api.trace("Valid connection from connection manager: \(String(describing: conn))")
            Task {
                store.documentEventPublisher.send(.repositoryWillChange)
                store.set(repository: ApiRepository(connection: conn))
                try? await store.fetchAll()
            }
        } else {
            Logger.shared.trace("App does not have any active connection")
        }
    }

    var body: some View {
        Group {
            if connectionManager.connection != nil {
                if let error = attachmentManager.error {
                    Text(String(describing: error))
                }

                if let url = attachmentManager.importUrls.first {
                    let remaining = totalInputs - attachmentManager.importUrls.count + 1
                    let title = "\(String(localized: .localizable.documentAdd)) (\(remaining) / \(totalInputs))"
                    VStack {
                        CreateDocumentView(
                            sourceUrl: url,
                            callback: internalCallback,
                            share: true,
                            title: title
                        )
                        .id(url)
                        // @FIXME: Gives a white band at the bottom, not ideal
                        .padding(.bottom, 40)

                        .environmentObject(store)
                        .environmentObject(errorController)
                        .environmentObject(connectionManager)
                        .accentColor(Color("AccentColor"))
                    }
                }
            } else {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Please log in using the app first!")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .alert(error, isPresented: $showingError) {
            Button("Ok", role: .cancel) {}
        }

        .task {
            if let conn = connectionManager.connection {
                store.set(repository: ApiRepository(connection: conn))
            }
        }

        .onChange(of: attachmentManager.importUrls) { _ in
            totalInputs = max(attachmentManager.importUrls.count, totalInputs)
        }

        .onChange(of: connectionManager.activeConnectionId) { _ in refreshConnection() }
        .onChange(of: connectionManager.connections) { _ in refreshConnection() }
    }
}
