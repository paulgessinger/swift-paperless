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

    @StateObject private var errorController = ErrorController()

    @Environment(\.scenePhase) var scenePhase

    @ObservedObject private var appSettings = AppSettings.shared

    private enum LockState {
        case initial, locked, unlocked
    }

    @State private var lockState = LockState.initial
    @State private var unlocking = false

    init() {
        _ = AppSettings.shared
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
                        if appSettings.enableBiometricAppLock, lockState == .locked || scenePhase == .inactive {
                            InactiveView()
                                .transition(.opacity)
                        }
                    }
            }
        }
        .environmentObject(errorController)

        .fullScreenCover(isPresented: $showLoginScreen) {
            LoginView(connectionManager: manager)
                .errorOverlay(errorController: errorController)
                .environmentObject(errorController)
        }

        .task {
            if lockState == .initial, appSettings.enableBiometricAppLock {
                lockState = .locked
            }

            Logger.shared.notice("Checking login status")
            refreshConnection()

            // @TODO: Remove in a few versions
            Task {
                try? await Task.sleep(for: .seconds(3))
                await manager.migrateToMultiServer()
            }
        }

        .onChange(of: manager.activeConnectionId) { _ in refreshConnection() }
        .onChange(of: manager.connections) { _ in refreshConnection() }

        .onChange(of: scenePhase) { value in
            switch value {
            case .inactive:
                Logger.shared.notice("App becomes inactive")

            case .background:
                Logger.shared.notice("App goes to background")
                if appSettings.enableBiometricAppLock, lockState == .unlocked {
                    Logger.shared.notice("Biometric lock is enabled: locking")
                    lockState = .locked
                }
            case .active:
                store?.startTaskPolling()

                Logger.shared.notice("App becomes active")
                if appSettings.enableBiometricAppLock, lockState == .locked {
                    Task {
                        if unlocking {
                            return
                        }
                        unlocking = true
                        defer { unlocking = false }
                        do {
                            Logger.shared.notice("App is locked, attempt biometric unlock")

                            if try await biometricAuthenticate() {
                                Logger.shared.notice("App is unlocked by biometric")
                                try? await Task.sleep(for: .seconds(1.0))
                                withAnimation {
                                    lockState = .unlocked
                                }
                            }
                        } catch {
                            Logger.shared.error("Error during biometric unlock: \(error)")
                            var message: String? = nil
                            if let biometricName = getBiometricName() {
                                message = String(localized: .settings.biometricLockEnableFailure(biometricName))
                            }
                            errorController.push(error: error, message: message)
                        }
                    }
                }

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
