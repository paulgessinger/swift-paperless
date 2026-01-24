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

  var body: some View {
    Form {
      Section {
        AppVersionView()

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
      } header: {
        Text(.settings(.versionInfoLabel))
      } footer: {
        Text(.settings(.resetAppVersionDescription))
      }

      NavigationLink {
        LogView()
      } label: {
        Label {
          Text(.settings(.logs))
            .accentColor(.primary)
        } icon: {
          Image(systemName: "text.word.spacing")
        }
      }

    }
    .navigationTitle(String(localized: .settings(.debugMenu)))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview("Debug menu") {
  NavigationStack {
    DebugMenuView()
  }
}

struct AppVersionView: View {
  private let version: AppVersion?
  private let config: AppConfiguration?

  init(version: AppVersion? = nil, config: AppConfiguration? = nil) {
    self.version = version ?? AppSettings.shared.currentAppVersion
    self.config = config ?? Bundle.main.appConfiguration
  }

  var body: some View {
    if let version, let config {
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
  }
}

#Preview("AppVersionView") {
  Form {
    Section {
      AppVersionView()
    }
    Section {
      AppVersionView(version: AppVersion(version: "1.0.0", build: "1"), config: .AppStore)
    }
    Section {
      AppVersionView(version: AppVersion(version: "1.0.0", build: "1"), config: .TestFlight)
    }
  }
}
