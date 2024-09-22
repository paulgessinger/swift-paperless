//
//  DebugMenuView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

import SwiftUI

struct DebugMenuView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                if let version = appSettings.currentAppVersion?.description {
                    LabeledContent(.settings(.appVersionTitle), value: version)
                } else {
                    Text(.localizable(.none))
                }
                Button {
                    AppSettings.shared.resetAppVersion()
                } label: {
                    Text(.settings(.debugResetAppVersion))
                }
            } footer: {
                Text(.settings(.resetAppVersionDescription))
            }

            Section {
                DocumentDetailViewVersionSelection()

                LoginViewSwitchView()
            } header: {
                Text(.settings(.experimentsTitle))
            } footer: {
                Text(.settings(.experimentsDescription))
            }
        }
        .navigationTitle(String(localized: .settings(.debugMenu)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    DebugMenuView()
}
