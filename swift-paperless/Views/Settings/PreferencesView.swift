//
//  PreferencesView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.08.23.
//

import SwiftUI

struct PreferencesView: View {
    @AppStorage(SettingsKeys.documentDeleteConfirmation)
    var documentDeleteConfirmation: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: .settings.documentDeleteConfirmationLabel), isOn: $documentDeleteConfirmation)
            } footer: {
                Text(.settings.documentDeleteConfirmationLabelDescription)
            }
        }
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
