//
//  BiometricLockManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.06.2024.
//

import Combine
import Foundation
import LocalAuthentication
import os

private func biometricAuthenticate() async throws -> Bool {
    let context = LAContext()
    var error: NSError?
    let reason = String(localized: .settings.biometricReason)

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        if let error {
            throw error
        } else {
            return false
        }
    }

    return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
}

@MainActor
class BiometricLockManager: ObservableObject {
    enum LockState {
        case initial, locked, unlocked
    }

    @Published
    private(set) var lockState = LockState.initial

    @Published
    private(set) var unlocking = false

    @Published
    var isEnabled: Bool {
        didSet {
            if !isEnabled {
                disable()
            } else {
                enable()
            }
        }
    }

    private let errorController: ErrorController

    init(errorController: ErrorController) {
        self.errorController = errorController
        isEnabled = AppSettings.shared.enableBiometricAppLock
    }

    func lockIfEnabled() {
        if AppSettings.shared.enableBiometricAppLock, lockState == .unlocked || lockState == .initial {
            Logger.biometric.notice("Biometric lock is enabled: locking")
            lockState = .locked
        }
    }

    func unlockIfEnabled() async {
        if AppSettings.shared.enableBiometricAppLock, lockState == .locked {
            if unlocking {
                return
            }
            unlocking = true
            defer { unlocking = false }
            do {
                Logger.biometric.notice("App is locked, attempt biometric unlock")

                if try await biometricAuthenticate() {
                    Logger.biometric.notice("App is unlocked by biometric")
                    try? await Task.sleep(for: .seconds(1.0))
                    lockState = .unlocked
                }
            } catch {
                Logger.biometric.error("Error during biometric unlock: \(error)")
                var message: String? = nil
                if let biometricName = Self.biometricName {
                    message = String(localized: .settings.biometricLockEnableFailure(biometricName))
                }
                errorController.push(error: error, message: message)
            }
        }
    }

    private func enable() {
        Task { @MainActor [errorController] in
            Logger.biometric.info("Enabling biometric lock")
            do {
                if try await biometricAuthenticate() {
                    Logger.biometric.info("Biometric lock enabled successfully")
                    try? await Task.sleep(for: .seconds(2))
                    AppSettings.shared.enableBiometricAppLock = true
                    lockState = .unlocked
                    Logger.biometric.info("Biometric lock wait complete")
                } else {
                    Logger.biometric.info("Biometric lock could not be enabled")
                    isEnabled = false
                }
            } catch {
                Logger.biometric.error("Error enabling biometric lock: \(error)")
                let biometricName = Self.biometricName ?? "UnknownID"
                errorController.push(error: error, message: String(localized: .settings.biometricLockEnableFailure(biometricName)))
                isEnabled = false
            }
        }
    }

    func disable() {
        Logger.biometric.info("Disabling biometric lock")
        AppSettings.shared.enableBiometricAppLock = false
    }

    static var biometricName: String? {
        var error: NSError?
        let laContext = LAContext()

        if !laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return nil
        }

        switch laContext.biometryType {
        case .touchID:
            return "TouchID"
        case .faceID:
            return "FaceID"
        case .none, .opticID:
            fallthrough
        @unknown default:
            return nil
        }
    }
}
