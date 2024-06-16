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
    @ObservedObject private var appSettings = AppSettings.shared

    @EnvironmentObject private var errorController: ErrorController
    @EnvironmentObject private var biometricLockManager: BiometricLockManager

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: .settings.documentDeleteConfirmationLabel),
                       isOn: $appSettings.documentDeleteConfirmation)
            } footer: {
                Text(.settings.documentDeleteConfirmationLabelDescription)
            }

            if let biometricName = BiometricLockManager.biometricName {
                Section {
                    Toggle(String(localized: .settings.useBiometricLock(biometricName)), isOn: $biometricLockManager.isEnabled)
                }
            }

            Section {
                Picker(selection: $appSettings.defaultSortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.localizedName).tag(field)
                    }
                } label: {
                    Text(.settings.defaultSortField)
                }

                Picker(selection: $appSettings.defaultSortOrder) {
                    Text(SortOrder.ascending.localizedName)
                        .tag(SortOrder.ascending)
                    Text(SortOrder.descending.localizedName)
                        .tag(SortOrder.descending)
                } label: {
                    Text(.settings.defaultSortOrder)
                }

                Picker(selection: $appSettings.defaultSearchMode) {
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
        .navigationTitle(Text(.settings.preferences))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Preferences") {
    PreferencesView()
}
