//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import AppShared
import Networking
import Persistence
import SwiftUI
import os

// MARK: - Settings View

struct SettingsView: View {
  @Environment(DocumentStore.self) private var store
  @Environment(ConnectionManager.self) private var connectionManager
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.openURL) private var openURL
  @Environment(\.dismiss) private var dismiss

  @State private var feedbackMailRequest: FeedbackMailRequest?
  @State private var showLoginSheet: Bool = false
  @State var identityManager = IdentityManager()

  private func checked(_ fn: @escaping () async throws -> Void) async {
    do {
      try await fn()
    } catch {
      errorController.push(error: error)
    }
  }

  private func openBugReportLink() {
    Task {
      let appVersion = AppSettings.shared.currentAppVersion?.description

      var url = URL(string: "https://github.com/paulgessinger/swift-paperless/issues/new")!

      var queryItems = [
        URLQueryItem(name: "template", value: "bug_report.yml"),
        URLQueryItem(name: "app_version", value: appVersion),
      ]

      if let backendVersion = (store.repository as? ApiRepository)?.backendVersion?
        .description
      {
        queryItems.append(URLQueryItem(name: "backend_version", value: backendVersion))
      }

      url = url.appending(queryItems: queryItems)

      openURL(url)
    }
  }

  private var organizationSection: some View {
    Section(String(localized: .settings(.organization))) {
      NavigationLink {
        ManageView<TagManager>()
          .navigationTitle(Text(.app(.tags)))
      } label: {
        Label(String(localized: .app(.tags)), systemImage: "tag.fill")
      }

      NavigationLink {
        ManageView<CorrespondentManager>()
          .navigationTitle(Text(.app(.correspondents)))
      } label: {
        Label(String(localized: .app(.correspondents)), systemImage: "person.fill")
      }

      NavigationLink {
        ManageView<DocumentTypeManager>()
          .navigationTitle(Text(.app(.documentTypes)))
      } label: {
        Label(String(localized: .app(.documentTypes)), systemImage: "doc.fill")
      }

      NavigationLink {
        ManageView<SavedViewManager>()
          .navigationTitle(Text(.app(.savedViews)))
      } label: {
        Label(
          String(localized: .app(.savedViews)),
          systemImage: "line.3.horizontal.decrease.circle.fill")
      }

      NavigationLink {
        ManageView<StoragePathManager>()
          .navigationTitle(Text(.app(.storagePaths)))
      } label: {
        Label(String(localized: .app(.storagePaths)), systemImage: "archivebox.fill")
      }

      NavigationLink {
        TrashView()
      } label: {
        Label(String(localized: .settings(.trashTitle)), systemImage: "trash.fill")
      }
    }
    .task {
      await checked { try await store.fetchAll() }
    }
  }

  private var detailSection: some View {
    Section(String(localized: .settings(.detailsTitle))) {
      if AppFeatures.enabled(.tipJar) {
        NavigationLink {
          TipJarView()
        } label: {
          Label(localized: .settings(.tipJarTitle), systemImage: "heart.fill")
            .labelStyle(.iconTint(.red))
        }
      }

      NavigationLink {
        LibrariesView()
      } label: {
        Label(String(localized: .settings(.detailsLibraries)), systemImage: "books.vertical.fill")
      }

      Button {
        UIApplication.shared.open(URL(string: "https://github.com/paulgessinger/swift-paperless/")!)
      } label: {
        Label {
          Text(.settings(.detailsSourceCode))
            .tint(.primary)
        } icon: {
          Image(systemName: "terminal.fill")
        }
      }

      NavigationLink {
        PrivacyView()
      } label: {
        Label(String(localized: .settings(.detailsPrivacy)), systemImage: "hand.raised.fill")
      }

      #if canImport(MessageUI)
        if FeedbackMail.canSendMail {
          LogRecordExportButton {
            (state: LogRecordExportButton.LogState, export: @escaping () -> Void) in
            switch state {
            case .none:
              Button {
                export()
              } label: {
                Label {
                  Text(.settings(.detailsFeedback))
                    .accentColor(.primary)
                } icon: {
                  Image(systemName: "paperplane.fill")
                }
              }

            case .loading:
              LogRecordExportButton.loadingView()

            case .loaded:
              Label(
                String(localized: .settings(.feedbackDone)), systemImage: "checkmark.circle.fill"
              )
              .accentColor(.primary)

            case .error(let error):
              Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
            }
          } change: { state in
            switch state {
            case .loaded(let logs):
              feedbackMailRequest = FeedbackMailRequest(
                logFileURL: logs, connectionManager: connectionManager)
            default:
              break
            }
          }
        }
      #endif

      NavigationLink {
        ReleaseNotesView()
      } label: {
        Label(localized: .settings(.releaseNotesLabel), systemImage: "newspaper.fill")
      }
    }
  }

  var advancedSection: some View {
    Section(String(localized: .settings(.advanced))) {

      NavigationLink {
        LogoChangeView()
      } label: {
        Label(localized: .settings(.logoChangeTitle), systemImage: "leaf.fill")
      }

      NavigationLink {
        DebugMenuView()
      } label: {
        Label(localized: .settings(.debugMenu), systemImage: "ladybug.fill")
      }

      Button {
        openBugReportLink()
      } label: {
        Label {
          Text(.settings(.reportBug))
            .accentColor(.primary)
        } icon: {
          Image(systemName: "exclamationmark.bubble.fill")
        }
      }

      NavigationLink {
        TLSListView(identityManager: identityManager)
      } label: {
        Label(localized: .settings(.identities), systemImage: "lock.fill")
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        ConnectionsView(
          connectionManager: connectionManager,
          showLoginSheet: $showLoginSheet)

        Section(String(localized: .settings(.preferences))) {
          NavigationLink {
            PreferencesView()
          } label: {
            Label(String(localized: .settings(.preferences)), systemImage: "dial.low.fill")
          }
        }

        organizationSection

        advancedSection

        detailSection
      }

      #if canImport(MessageUI)
        .feedbackMailSheet(item: $feedbackMailRequest)
      #endif

      .sheet(isPresented: $showLoginSheet) {
        LoginView(connectionManager: connectionManager, initial: false)
          .environmentObject(errorController)
      }

      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
      }

      .navigationTitle(Text(.settings(.title)))
      .navigationBarTitleDisplayMode(.large)
    }
  }
}

#Preview("SettingsView") {
  @Previewable @State var store = DocumentStore.preview()
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @State var connectionManager = ConnectionManager(
    database: try! Database.inMemory())

  VStack {
  }
  .sheet(isPresented: .constant(true)) {
    SettingsView()
      .environment(store)
      .environment(connectionManager)
  }
}
