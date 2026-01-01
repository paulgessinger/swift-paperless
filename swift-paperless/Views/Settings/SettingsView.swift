//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import Networking
import SwiftUI
import os

#if canImport(MessageUI)
  import MessageUI
#endif

// MARK: - Settings View

struct SettingsView: View {
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var connectionManager: ConnectionManager
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.openURL) private var openURL

  @State private var feedbackLogs: URL? = nil
  @State private var showMailSheet: Bool = false
  @State private var showLoginSheet: Bool = false
  @State private var result: Result<MFMailComposeResult, any Error>? = nil
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
          .navigationTitle(Text(.localizable(.tags)))
      } label: {
        Label(String(localized: .localizable(.tags)), systemImage: "tag.fill")
      }

      NavigationLink {
        ManageView<CorrespondentManager>()
          .navigationTitle(Text(.localizable(.correspondents)))
      } label: {
        Label(String(localized: .localizable(.correspondents)), systemImage: "person.fill")
      }

      NavigationLink {
        ManageView<DocumentTypeManager>()
          .navigationTitle(Text(.localizable(.documentTypes)))
      } label: {
        Label(String(localized: .localizable(.documentTypes)), systemImage: "doc.fill")
      }

      NavigationLink {
        ManageView<SavedViewManager>()
      } label: {
        Label(
          String(localized: .localizable(.savedViews)),
          systemImage: "line.3.horizontal.decrease.circle.fill")
      }

      NavigationLink {
        ManageView<StoragePathManager>()
          .navigationTitle(Text(.localizable(.storagePaths)))
      } label: {
        Label(String(localized: .localizable(.storagePaths)), systemImage: "archivebox.fill")
      }
    }
    .task {
      await checked(store.fetchAll)
    }
  }

  private var detailSection: some View {
    Section(String(localized: .settings(.detailsTitle))) {
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
        if MFMailComposeViewController.canSendMail() {
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
              feedbackLogs = logs
            default:
              break
            }
          }
        }
      #endif

      NavigationLink {
        AppVersionView()
      } label: {
        Label(localized: .settings(.versionInfoLabel), systemImage: "info.bubble.fill")
      }

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
        LogView()
      } label: {
        Label {
          Text(.settings(.logs))
            .accentColor(.primary)
        } icon: {
          Image(systemName: "text.word.spacing")
        }
      }

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
      .sheet(isPresented: $showMailSheet) {
        // @FIXME: Weird empty bottom row that seems to come from MessageUI itself
        MailView(result: $result, isPresented: $showMailSheet) { vc in
          vc.setToRecipients(["swift-paperless@paulgessinger.com"])
          if let feedbackLogs, let data = try? Data(contentsOf: feedbackLogs) {
            vc.addAttachmentData(data, mimeType: "text/plain", fileName: "logs.txt")
          }

          let version = Bundle.main.releaseVersionNumber ?? "?"
          let build = Bundle.main.buildVersionNumber ?? "?"

          vc.setMessageBody(
            """
            ---
            App version: \(version) (\(build)), \(Bundle.main.appConfiguration.rawValue)
            """, isHTML: false)
        }
      }
    #endif

    .sheet(isPresented: $showLoginSheet) {
      LoginView(connectionManager: connectionManager, initial: false)
        .environmentObject(errorController)
        .errorOverlay(errorController: errorController, offset: 15)
    }

    .onChange(of: feedbackLogs) {
      showMailSheet = true
    }

    .navigationTitle(Text(.settings(.title)))
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct PreviewHelper: View {
  @StateObject var store = DocumentStore(repository: PreviewRepository())

  @StateObject var errorController = ErrorController()
  @StateObject var connectionManager = ConnectionManager()

  var body: some View {
    NavigationStack {
      SettingsView()
        .navigationBarTitleDisplayMode(.inline)
    }
    .environmentObject(store)
    .environmentObject(connectionManager)
    .errorOverlay(errorController: errorController)
  }
}

#Preview("SettingsView") {
  PreviewHelper()
}
