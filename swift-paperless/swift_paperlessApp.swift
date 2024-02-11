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
    @StateObject private var filterModel = FilterModel()

    @StateObject private var manager = ConnectionManager()

    @StateObject private var errorController = ErrorController()

    @Environment(\.scenePhase) var scenePhase
    @AppStorage(SettingsKeys.enableBiometricAppLock)
    private var enableBiometricAppLock: Bool = false

    private enum LockState {
        case initial, locked, unlocked
    }

    @State private var lockState = LockState.initial
    @State private var unlocking = false

    var body: some View {
        Group {
            if manager.state == .valid, storeReady {
                DocumentView()
                    .errorOverlay(errorController: errorController)
                    .environmentObject(store!)
                    .environmentObject(manager)
                    .environmentObject(filterModel)

                    .overlay {
                        if enableBiometricAppLock, lockState == .locked || scenePhase == .inactive {
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
            if lockState == .initial, enableBiometricAppLock {
                lockState = .locked
            }

            Logger.shared.notice("Checking login status")
            await manager.check()
        }

        .onChange(of: manager.state) { value in
            showLoginScreen = value == .invalid
            if let conn = manager.connection {
                store = DocumentStore(repository: ApiRepository(connection: conn))
                storeReady = true
            }
        }

        .onChange(of: scenePhase) { value in
            switch value {
            case .inactive:
                Logger.shared.notice("App becomes inactive")

            case .background:
                Logger.shared.notice("App goes to background")
                if enableBiometricAppLock, lockState == .unlocked {
                    Logger.shared.notice("Biometric lock is enabled: locking")
                    lockState = .locked
                }
            case .active:
                Logger.shared.notice("App becomes active")
                if enableBiometricAppLock, lockState == .locked {
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
