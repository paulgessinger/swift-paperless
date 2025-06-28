import DataModel
import LocalAuthentication
import os
import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    @EnvironmentObject private var errorController: ErrorController
    @EnvironmentObject private var biometricLockManager: BiometricLockManager
    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: .settings(.documentDeleteConfirmationLabel)),
                       isOn: $appSettings.documentDeleteConfirmation)
            } footer: {
                Text(.settings(.documentDeleteConfirmationLabelDescription))
            }

            Section {
                Toggle(String(localized: .settings(.showDocumentDetailPropertyBar)),
                       isOn: $appSettings.showDocumentDetailPropertyBar)
            } footer: {
                Text(.settings(.showDocumentDetailPropertyBarDescription))
            }

            if let biometricName = BiometricLockManager.biometricName {
                Section {
                    Toggle(String(localized: .settings(.useBiometricLock(biometricName))),
                           isOn: $biometricLockManager.isEnabled)
                }
            }

            Section {
                Picker(selection: $appSettings.defaultSortField) {
                    ForEach(SortField.allCases, id: \.self) { field in
                        Text(field.localizedName(customFields: store.customFields)).tag(field)
                    }
                } label: {
                    Text(.settings(.defaultSortField))
                }

                Picker(selection: $appSettings.defaultSortOrder) {
                    Text(DataModel.SortOrder.ascending.localizedName)
                        .tag(DataModel.SortOrder.ascending)
                    Text(DataModel.SortOrder.descending.localizedName)
                        .tag(DataModel.SortOrder.descending)
                } label: {
                    Text(.settings(.defaultSortOrder))
                }

                Picker(selection: $appSettings.defaultSearchMode) {
                    ForEach(FilterState.SearchMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                } label: {
                    Text(.settings(.defaultSearchModeLabel))
                }
            } header: {
                Text(.localizable(.filtering))
            } footer: {
                Text(.settings(.defaultSearchModeDescription))
            }
        }
        .navigationTitle(Text(.settings(.preferences)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Preferences") {
    PreferencesView()
}
