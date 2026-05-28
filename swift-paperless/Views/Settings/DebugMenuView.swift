//
//  DebugMenuView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

import AppShared
import Common
import DataModel
import Persistence
import SwiftUI

struct DebugMenuView: View {
  @EnvironmentObject private var connectionManager: ConnectionManager
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
            Text(.app(.none))
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
        LogView(connectionManager: connectionManager)
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
      Button(.app(.ok)) {}
    } message: {
      Text(.settings(.appVersionResetMessage))
    }
  }
}

#Preview("Debug menu") {
  @Previewable @StateObject var connectionManager = ConnectionManager(
    database: try! Database.inMemory())

  NavigationStack {
    DebugMenuView()
      .environmentObject(connectionManager)
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
        Text(.app(.none))
      }
    } label: {
      Text(.settings(.appVersionLabel))
    }

    LabeledContent {
      if let version {
        Text("\(version.build)")
      } else {
        Text(.app(.none))
      }
    } label: {
      Text(.settings(.appBuildNumberLabel))
    }

    LabeledContent {
      if let config {
        Text(config.rawValue)
      } else {
        Text(.app(.none))
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
