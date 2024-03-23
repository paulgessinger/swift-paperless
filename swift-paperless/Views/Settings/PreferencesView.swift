import LocalAuthentication
import os
import SwiftUI

struct PreferencesView: View {
    @AppStorage(SettingsKeys.documentDeleteConfirmation)
    private var documentDeleteConfirmation: Bool = true

    @AppStorage(SettingsKeys.enableBiometricAppLock)
    private var enableBiometricAppLock: Bool = false

    @State private var enableBiometricToggle = false

    @State private var biometricName: String? = nil

    @EnvironmentObject private var errorController: ErrorController

    init() {
        _enableBiometricToggle = State(initialValue: enableBiometricAppLock)
        _biometricName = State(initialValue: getBiometricName())
    }

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: .settings.documentDeleteConfirmationLabel), isOn: $documentDeleteConfirmation)
            } footer: {
                Text(.settings.documentDeleteConfirmationLabelDescription)
            }

            if let biometricName {
                Section {
                    Toggle(String(localized: .settings.useBiometricLock(biometricName)), isOn: $enableBiometricToggle)
                }
            }
        }

        .onChange(of: enableBiometricToggle) { value in
            if !value {
                Logger.shared.notice("Biometric lock disabled")
                enableBiometricAppLock = false
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
                        try? await Task.sleep(for: .seconds(2))
                        enableBiometricAppLock = true
                    } else {
                        Logger.shared.notice("Biometric lock could not be enabled")
                        enableBiometricToggle = false
                    }
                } catch {
                    Logger.shared.error("Error enabling biometric lock: \(error)")
                    errorController.push(error: error, message: String(localized: .settings.biometricLockEnableFailure(biometricName)))
                    enableBiometricToggle = false
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
