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
import os

struct DebugMenuView: View {
  @Environment(ConnectionManager.self) private var connectionManager
  @Environment(DocumentStore.self) private var store
  @EnvironmentObject private var errorController: ErrorController
  private let appSettings = AppSettings.shared
  @State private var showResetConfirmation = false
  @State private var exportResult: ExportResult?
  @State private var showClearCacheConfirmation = false
  @State private var showCacheClearedConfirmation = false

  /// Outcome of the legacy-storage export, reported in an alert rather than
  /// through `ErrorController` so it stays visible above the settings sheet.
  private enum ExportResult: Identifiable {
    case exported(count: Int)
    case failed(String)

    var id: String {
      switch self {
      case .exported(let count): "exported-\(count)"
      case .failed(let message): "failed-\(message)"
      }
    }
  }

  private func exportConnectionsToLegacyStorage() {
    do {
      let count = try connectionManager.exportConnectionsToLegacyStorage()
      exportResult = .exported(count: count)
    } catch {
      Logger.shared.error("Legacy connection export failed: \(error)")
      exportResult = .failed(error.localizedDescription)
    }
  }

  private func clearCache() async {
    do {
      try await store.wipeLocalCache()
      showCacheClearedConfirmation = true
    } catch {
      Logger.shared.error("Failed to clear local cache: \(error)")
      errorController.push(error: error)
    }
  }

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

      // Debug-only affordance: not localized on purpose, so debug strings
      // don't reach translators.
      Section {
        Button {
          exportConnectionsToLegacyStorage()
        } label: {
          Label {
            Text(verbatim: "Export servers to legacy storage")
              .accentColor(.primary)
          } icon: {
            Image(systemName: "square.and.arrow.up.on.square")
          }
        }
      } footer: {
        Text(
          verbatim: """
            Writes the current servers back to the storage format used before \
            the local database. The database restores from it on first launch, \
            so you can export, wipe the database, and relaunch to test recovery.
            """)
      }

      Section {
        Button {
          showClearCacheConfirmation = true
        } label: {
          Label {
            Text(.settings(.clearCache))
          } icon: {
            Image(systemName: "trash")
          }
        }
        .confirmationDialog(
          String(localized: .settings(.clearCacheConfirmationTitle)),
          isPresented: $showClearCacheConfirmation,
          titleVisibility: .visible
        ) {
          Button(role: .destructive) {
            Task { await clearCache() }
          } label: {
            Text(.settings(.clearCache))
          }
          Button(.app(.cancel), role: .cancel) {}
        } message: {
          Text(.settings(.clearCacheConfirmation))
        }
      } header: {
        Text(.settings(.localStorage))
      } footer: {
        Text(.settings(.localStorageDescription))
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
    .alert(item: $exportResult) { result in
      switch result {
      case .exported(let count):
        Alert(
          title: Text(verbatim: "Export complete"),
          message: Text(verbatim: "Servers exported: \(count)"),
          dismissButton: .default(Text(.app(.ok))))
      case .failed(let message):
        Alert(
          title: Text(verbatim: "Export failed"),
          message: Text(verbatim: message),
          dismissButton: .default(Text(.app(.ok))))
      }
    }
    .alert(
      String(localized: .settings(.cacheCleared)),
      isPresented: $showCacheClearedConfirmation
    ) {
      Button(.app(.ok)) {}
    }
  }
}

#Preview("Debug menu") {
  @Previewable @State var connectionManager = ConnectionManager(
    database: try! Database.inMemory())
  @Previewable @State var store = DocumentStore.preview()

  NavigationStack {
    DebugMenuView()
      .environment(connectionManager)
      .environment(store)
      .environmentObject(ErrorController())
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
