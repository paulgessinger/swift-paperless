//
//  AppVersionView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.05.2024.
//

import Foundation
import SwiftUI

struct AppVersionView: View {
    private typealias Info = (version: String, build: String, config: AppConfiguration)
    @State private var info: Info?

    private func update(info _: Info) {}

    var body: some View {
        Form {
            if let info {
                LabeledContent {
                    Text(info.version)
                } label: {
                    Text(.settings(.appVersionLabel))
                }

                LabeledContent {
                    Text(info.build)
                } label: {
                    Text(.settings(.appBuildNumberLabel))
                }

                LabeledContent {
                    Text(info.config.rawValue)
                } label: {
                    Text(.settings(.appConfigurationLabel))
                }
            }
        }
        .navigationTitle(String(localized: .settings(.versionInfoLabel)))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            info = await Task.detached {
                Info(version: Bundle.main.releaseVersionNumber ?? "?",
                     build: Bundle.main.buildVersionNumber ?? "?",
                     config: Bundle.main.appConfiguration)
            }.value
        }
    }
}

#Preview {
    AppVersionView()
}
