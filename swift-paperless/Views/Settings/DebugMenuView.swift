//
//  DebugMenuView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

import Common
import DataModel
import SwiftUI

struct DebugMenuView: View {
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var showExperiments = false

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

            if showExperiments {
                Section {
                    DocumentDetailViewVersionSelection()

                    LoginViewSwitchView()
                } header: {
                    Text(.settings(.experimentsTitle))
                } footer: {
                    Text(.settings(.experimentsDescription))
                }
            }
        }
        .navigationTitle(String(localized: .settings(.debugMenu)))
        .navigationBarTitleDisplayMode(.inline)

        .task {
            showExperiments = Bundle.main.appConfiguration != .AppStore
        }
    }
}

#Preview("Debug menu") {
    NavigationStack {
        DebugMenuView()
    }
}
