//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Networking
import os
import SwiftUI

struct MainView: View {
    @State private var showLoginScreen = false

    @State private var storeReady = false
    @State private var showLoadingScreen = false
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

    private func refreshConnection(animated: Bool) {
        Logger.api.info("Connection info changed, reloading!")
        if let conn = manager.connection {
            storeReady = false
            if animated {
                showLoadingScreen = true
            }

            let sleep = { (duration: Duration) async in
                if animated {
                    try? await Task.sleep(for: duration)
                }
            }

            Logger.api.info("Valid connection from connection manager: \(String(describing: conn))")
            if let store {
                Task {
                    await sleep(.seconds(0.1))
                    store.eventPublisher.send(.repositoryWillChange)
                    await sleep(.seconds(0.3))
                    await store.set(repository: ApiRepository(connection: conn))
                    storeReady = true
                    try? await store.fetchAll()
                    store.startTaskPolling()
                    await sleep(.seconds(0.3))
                    showLoadingScreen = false
                }
            } else {
                Task {
                    store = await DocumentStore(repository: ApiRepository(connection: conn))
                    storeReady = true
                    try? await store!.fetchAll()
                    store!.startTaskPolling()
                    showLoadingScreen = false
                }
            }
            showLoginScreen = false
        } else {
            storeReady = false
            Logger.shared.trace("App does not have any active connection, show login screen")
            showLoginScreen = true
        }
    }

    var body: some View {
        VStack {
            ZStack {
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

                VStack {
                    if manager.connection == nil || showLoadingScreen {
                        MainLoadingView(url: manager.connection?.url.absoluteString,
                                        manager: manager)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.white)
                    }
                }
                .animation(.default, value: showLoadingScreen)
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
            refreshConnection(animated: false)

            // @TODO: Remove in a few versions
            Task {
                try? await Task.sleep(for: .seconds(3))
                await manager.migrateToMultiServer()
            }
        }

        .onReceive(manager.eventPublisher) { event in
            switch event {
            case let .connectionChange(animated):
                refreshConnection(animated: animated)
            }
        }

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
