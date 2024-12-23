//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import os
import SwiftUI

private struct LoadingView: View {
    let url: String?
    let manager: ConnectionManager

    @State private var showProgress = false
    @State private var showFailSafe = false

    var body: some View {
        VStack {
            LogoView()

            if showProgress {
                ProgressView()
                    .controlSize(.large)
            }

            if showFailSafe {
                Text(.localizable(.loginFailSafe(url ?? "???")))
                    .padding(.horizontal)
                    .padding(.top, 50)

                Button {
                    showFailSafe = false
                    manager.logout()
                } label: {
                    Label(String(localized: .localizable(.logout)), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundColor(Color.red)
                .bold()
                .padding(.top)
            }
        }

        .animation(.default, value: showProgress)
        .animation(.default, value: showFailSafe)

        .task {
            try? await Task.sleep(for: .seconds(1))
            showProgress = true
            try? await Task.sleep(for: .seconds(15))
            showFailSafe = true
        }
    }
}

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
            Logger.api.info("Valid connection from connection manager: \(String(describing: conn))")
            if let store {
                Task {
                    store.eventPublisher.send(.repositoryWillChange)
                    try? await Task.sleep(for: .seconds(0.3))
                    await store.set(repository: ApiRepository(connection: conn))
                    Task {
                        try? await Task.sleep(for: .seconds(0.25))
                        storeReady = true
                    }
                    try? await store.fetchAll()
                    store.startTaskPolling()
                }
            } else {
                Task {
                    store = await DocumentStore(repository: ApiRepository(connection: conn))
                    storeReady = true
                    try? await store!.fetchAll()
                    store!.startTaskPolling()
                }
            }
            showLoginScreen = false
        } else {
            Logger.shared.trace("App does not have any active connection, show login screen")
            showLoginScreen = true
        }
    }

    var body: some View {
        VStack {
            ZStack {
                if manager.connection == nil || !storeReady {
                    VStack {
                        if !showLoginScreen {
                            LoadingView(url: manager.connection?.url.absoluteString,
                                        manager: manager)
                        }
                    }
                    .animation(.default, value: showLoginScreen)
                } else {
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
        }
        .animation(.default, value: storeReady)

        .environmentObject(errorController)
        .environmentObject(biometricLockManager)

        .fullScreenCover(isPresented: $showLoginScreen) {
            LoginView(connectionManager: manager)
                .errorOverlay(errorController: errorController)
                .environmentObject(errorController)
                .interactiveDismissDisabled()
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
