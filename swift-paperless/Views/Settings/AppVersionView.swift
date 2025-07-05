//
//  AppVersionView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.05.2024.
//

import Common
import Foundation
import SwiftUI

struct AppVersionView: View {
  private let version: AppVersion?
  private let config: AppConfiguration?

  init(version: AppVersion? = nil, config: AppConfiguration? = nil) {
    self.version = version ?? AppSettings.shared.currentAppVersion
    self.config = config ?? Bundle.main.appConfiguration
  }

  var body: some View {
    if let version, let config {
      Form {
        LabeledContent {
          Text(version.version.description)
        } label: {
          Text(.settings(.appVersionLabel))
        }

        LabeledContent {
          Text("\(version.build)")
        } label: {
          Text(.settings(.appBuildNumberLabel))
        }

        LabeledContent {
          Text(config.rawValue)
        } label: {
          Text(.settings(.appConfigurationLabel))
        }
      }
      .navigationTitle(String(localized: .settings(.versionInfoLabel)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

#Preview {
  VStack {
    AppVersionView()
    AppVersionView(version: AppVersion(version: "1.0.0", build: "1"), config: .AppStore)
    AppVersionView(version: AppVersion(version: "1.0.0", build: "1"), config: .TestFlight)
  }
}
