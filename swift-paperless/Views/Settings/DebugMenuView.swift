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
  @State private var showResetConfirmation = false

  var body: some View {
    Form {
      Section {
        AppVersionView()

        LabeledContent(.settings(.appVersionTitle)) {
          if let version = appSettings.currentAppVersion?.description {
            Text(version)
          } else {
            Text(.localizable(.none))
          }
        }
        Button {
          AppSettings.shared.resetAppVersion()
          showResetConfirmation = true
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
    .alert(String(localized: .settings(.appVersionResetTitle)), isPresented: $showResetConfirmation)
    {
      Button(.localizable(.ok)) {}
    } message: {
      Text(.settings(.appVersionResetMessage))
    }
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
    LabeledContent {
      if let version {
        Text(version.version.description)
      } else {
        Text(.localizable(.none))
      }
    } label: {
      Text(.settings(.appVersionLabel))
    }

    LabeledContent {
      if let version {
        Text("\(version.build)")
      } else {
        Text(.localizable(.none))
      }
    } label: {
      Text(.settings(.appBuildNumberLabel))
    }

    LabeledContent {
      if let config {
        Text(config.rawValue)
      } else {
        Text(.localizable(.none))
      }
    } label: {
      Text(.settings(.appConfigurationLabel))
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
