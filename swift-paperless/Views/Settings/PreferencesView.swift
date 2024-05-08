import LocalAuthentication
import os
import SwiftUI

struct TestView: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        LabeledContent {
            Text("\(settings.documentDeleteConfirmation)")
        } label: {
            Text("ObservedObject")
        }
    }
}

struct PreferencesView: View {
    @AppSetting(\.$documentDeleteConfirmation)
    var documentDeleteConfirmation

    @AppSetting(\.$defaultSearchMode)
    var defaultSearchMode

    @AppSetting(\.$defaultSortOrder)
    var defaultSortOrder

    @AppSetting(\.$defaultSortField)
    var defaultSortField

    @State private var enableBiometricToggle = false

    @State private var biometricName: String? = nil

    @EnvironmentObject private var errorController: ErrorController

    init() {
        _enableBiometricToggle = State(initialValue: AppSettings.shared.enableBiometricAppLock)
        _biometricName = State(initialValue: getBiometricName())
    }

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: .settings.documentDeleteConfirmationLabel),
                       isOn: $documentDeleteConfirmation)
            } footer: {
                Text(.settings.documentDeleteConfirmationLabelDescription)
            }

            if let biometricName {
                Section {
                    Toggle(String(localized: .settings.useBiometricLock(biometricName)), isOn: $enableBiometricToggle)
                }
            }

            Section {
                Picker(selection: $defaultSortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.localizedName).tag(field)
                    }
                } label: {
                    Text(.settings.defaultSortField)
                }

                Picker(selection: $defaultSortOrder) {
                    Text(SortOrder.ascending.localizedName)
                        .tag(SortOrder.ascending)
                    Text(SortOrder.descending.localizedName)
                        .tag(SortOrder.descending)
                } label: {
                    Text(.settings.defaultSortOrder)
                }

                Picker(selection: $defaultSearchMode) {
                    ForEach(FilterState.SearchMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                } label: {
                    Text(.settings.defaultSearchModeLabel)
                }
            } header: {
                Text(.localizable.filtering)
            } footer: {
                Text(.settings.defaultSearchModeDescription)
            }
        }

        .onChange(of: enableBiometricToggle) { value in
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
                        try? await Task.sleep(for: .seconds(2))
                        AppSettings.shared.enableBiometricAppLock = true
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

#Preview("Preferences") {
    PreferencesView()
}
