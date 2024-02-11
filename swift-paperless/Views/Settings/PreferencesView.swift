import LocalAuthentication
import os
import SwiftUI

struct PreferencesView: View {
    @AppStorage(SettingsKeys.documentDeleteConfirmation)
    private var documentDeleteConfirmation: Bool = true

    @AppStorage(SettingsKeys.enableBiometricAppLock)
    private var enableBiometricAppLock: Bool = false

    @State private var biometricName: String? = nil

    @EnvironmentObject private var errorController: ErrorController

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: .settings.documentDeleteConfirmationLabel), isOn: $documentDeleteConfirmation)
            } footer: {
                Text(.settings.documentDeleteConfirmationLabelDescription)
            }

            if let biometricName {
                Section {
                    Toggle(String(localized: .settings.useBiometricLock(biometricName)), isOn: $enableBiometricAppLock)
                }
            }
        }

        .task { biometricName = getBiometricName() }

        .onChange(of: enableBiometricAppLock) { value in
            if !value {
                Logger.shared.notice("Biometric lock disabled")
                return
            }

            guard let biometricName else {
                Logger.shared.error("Biometric info returned false, but activation was requested")
                return
            }

            Logger.shared.notice("Attempt to enable biometric lock")

            Task {
                do {
                    if try await biometricAuthenticate() {
                        Logger.shared.notice("Biometric lock enabled successfully")
                    } else {
                        Logger.shared.notice("Biometric lock could not be enabled")
                        enableBiometricAppLock = false
                    }
                } catch {
                    Logger.shared.error("Error enabling biometric lock: \(error)")
                    errorController.push(error: error, message: String(localized: .settings.biometricLockEnableFailure(biometricName)))
                    enableBiometricAppLock = false
                }
            }
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
