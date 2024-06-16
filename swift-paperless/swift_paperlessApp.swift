//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Collections
import os
import SwiftUI

struct MainView: View {
    @State private var showLoginScreen = false

    @State private var storeReady = false
    @State private var store: DocumentStore?

    @StateObject private var manager = ConnectionManager()

    @StateObject private var errorController: ErrorController

    @Environment(\.scenePhase) var scenePhase

    @ObservedObject private var appSettings = AppSettings.shared

    @StateObject private var releaseNotesModel = ReleaseNotesViewModel()

    @StateObject private var biometricLockManager: BiometricLockManager

    init() {
        _ = AppSettings.shared
        let errorController = ErrorController()
        _errorController = StateObject(wrappedValue: errorController)
        _biometricLockManager = StateObject(wrappedValue: BiometricLockManager(errorController: errorController))
    }

    private func refreshConnection() {
        Logger.api.info("Connection info changed, reloading!")

        storeReady = false
        if let conn = manager.connection {
            Logger.api.trace("Valid connection from connection manager: \(String(describing: conn))")
            if let store {
                Task {
                    store.eventPublisher.send(.repositoryWillChange)
                    try? await Task.sleep(for: .seconds(0.3))
                    store.set(repository: ApiRepository(connection: conn))
                    try? await store.fetchAll()
                    store.startTaskPolling()
                }
            } else {
                store = DocumentStore(repository: ApiRepository(connection: conn))
                Task {
                    try? await store!.fetchAll()
                    store!.startTaskPolling()
                }
            }
            storeReady = true
            showLoginScreen = false
        } else {
            Logger.shared.trace("App does not have any active connection, show login screen")
            showLoginScreen = true
        }
    }

    var body: some View {
        Group {
            if manager.connection != nil, storeReady {
                DocumentView()
                    .errorOverlay(errorController: errorController)
                    .environmentObject(store!)
                    .environmentObject(manager)

                    .overlay {
                        if AppSettings.shared.enableBiometricAppLock, biometricLockManager.lockState == .locked || scenePhase == .inactive {
                            InactiveView()
                                .transition(.opacity)
                        }
                    }
            }
        }
        .environmentObject(errorController)
        .environmentObject(biometricLockManager)

        .fullScreenCover(isPresented: $showLoginScreen) {
            LoginView(connectionManager: manager)
                .errorOverlay(errorController: errorController)
                .environmentObject(errorController)
        }

        .fullScreenCover(isPresented: $releaseNotesModel.showReleaseNotes) {
            ReleaseNotesView(releaseNotesModel: releaseNotesModel)
        }

        .task {
            biometricLockManager.lockIfEnabled()

            Logger.shared.notice("Checking login status")
            refreshConnection()

            // @TODO: Remove in a few versions
            Task {
                try? await Task.sleep(for: .seconds(3))
                await manager.migrateToMultiServer()
            }
        }

        .onChange(of: manager.activeConnectionId) { refreshConnection() }
        .onChange(of: manager.connections) { refreshConnection() }

        .onChange(of: scenePhase) { _, value in
            switch value {
            case .inactive:
                Logger.shared.notice("App becomes inactive")

            case .background:
                Logger.shared.notice("App goes to background")
                biometricLockManager.lockIfEnabled()

            case .active:
                store?.startTaskPolling()

                Logger.shared.notice("App becomes active")

                Task { await biometricLockManager.unlockIfEnabled() }

            default:
                break
            }
        }
    }
}

@main
struct swift_paperlessApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
