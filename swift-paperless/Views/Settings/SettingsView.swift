//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import MessageUI
import os
import SwiftUI
import SwiftUINavigation

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var connectionManager: ConnectionManager
    @EnvironmentObject private var errorController: ErrorController

    @State private var extraHeaders: [ConnectionManager.HeaderValue] = []

    @State private var feedbackLogs: String? = nil
    @State private var showMailSheet: Bool = false
    @State private var result: Result<MFMailComposeResult, Error>? = nil

    private func checkedDetached(_ fn: @escaping () async throws -> Void) async {
        Task.detached {
            do {
                try await fn()
            } catch {
                await errorController.push(error: error)
            }
        }
    }

    var body: some View {
        List {
            Section(String(localized: .settings.activeServer)) {
                Text(connectionManager.apiHost ?? "No server")
            }
            Section(String(localized: .settings.organization)) {
                NavigationLink {
                    ManageView<TagManager>(store: store)
                        .navigationTitle(Text(.localizable.tags))
                        .task { await checkedDetached(store.fetchAllTags) }
                } label: {
                    Label(String(localized: .localizable.tags), systemImage: "tag.fill")
                }

                NavigationLink {
                    ManageView<CorrespondentManager>(store: store)
                        .navigationTitle(Text(.localizable.correspondents))
                        .task { await checkedDetached(store.fetchAllCorrespondents) }
                } label: {
                    Label(String(localized: .localizable.correspondents), systemImage: "person.fill")
                }

                NavigationLink {
                    ManageView<DocumentTypeManager>(store: store)
                        .navigationTitle(Text(.localizable.documentTypes))
                        .task { await checkedDetached(store.fetchAllDocumentTypes) }
                } label: {
                    Label(String(localized: .localizable.documentTypes), systemImage: "doc.fill")
                }

                NavigationLink {
                    ManageView<SavedViewManager>(store: store)
                        .navigationTitle(Text(.localizable.savedViews))
                        .task { await checkedDetached(store.fetchAllDocumentTypes) }
                } label: {
                    Label(String(localized: .localizable.savedViews), systemImage: "line.3.horizontal.decrease.circle.fill")
                }

                NavigationLink {
                    ManageView<StoragePathManager>(store: store)
                        .navigationTitle(Text(.localizable.storagePaths))
                        .task { await checkedDetached(store.fetchAllStoragePaths) }
                } label: {
                    Label(String(localized: .localizable.storagePaths), systemImage: "archivebox.fill")
                }
            }

            Section(String(localized: .settings.preferences)) {
                NavigationLink {
                    PreferencesView()
                        .navigationTitle(Text(.settings.preferences))
                } label: {
                    Label(String(localized: .settings.preferences), systemImage: "dial.low.fill")
                }
            }

            Section(String(localized: .settings.advanced)) {
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Label(String(localized: .login.extraHeaders), systemImage: "list.bullet.rectangle.fill")
                }

                LogRecordExportButton()
            }

            Section(String(localized: .settings.detailsTitle)) {
                NavigationLink {
                    LibrariesView()
                } label: {
                    Label(String(localized: .settings.detailsLibraries), systemImage: "books.vertical.fill")
                }

                Button {
                    UIApplication.shared.open(URL(string: "https://github.com/paulgessinger/swift-paperless/")!)
                } label: {
                    Label(String(localized: .settings.detailsSourceCode), systemImage: "terminal.fill")
                        .accentColor(.primary)
                }

                NavigationLink {
                    PrivacyView()
                } label: {
                    Label(String(localized: .settings.detailsPrivacy), systemImage: "hand.raised.fill")
                }

                if MFMailComposeViewController.canSendMail() {
                    LogRecordExportButton { (state: LogRecordExportButton.LogState, export: @escaping () -> Void) in
                        switch state {
                        case .none:
                            Button {
                                export()
                            } label: {
                                Label(String(localized: .settings.detailsFeedback), systemImage: "paperplane.fill")
                                    .accentColor(.primary)
                            }

                        case .loading:
                            LogRecordExportButton.loadingView()

                        case .loaded:
                            Label(String(localized: .settings.feedbackDone), systemImage: "checkmark.circle.fill")
                                .accentColor(.primary)

                        case let .error(error):
                            Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    } change: { state in
                        switch state {
                        case let .loaded(logs):
                            feedbackLogs = logs
                        default:
                            break
                        }
                    }
                }
            }
        }

        .onChange(of: extraHeaders) { value in
            Logger.shared.trace("Saving new set of extra headers: \(value)")
            connectionManager.extraHeaders = value
            store.set(repository: ApiRepository(connection: connectionManager.connection!))
        }

        .sheet(isPresented: $showMailSheet) {
            // @FIXME: Weird empty bottom row that seems to come from MessageUI itself
            MailVilew(result: $result, isPresented: $showMailSheet) { vc in
                vc.setToRecipients(["swift-paperless@paulgessinger.com"])
                if let data = feedbackLogs?.data(using: .utf8) {
                    vc.addAttachmentData(data, mimeType: "text/plain", fileName: "logs.txt")
                }
            }
        }

        .onChange(of: feedbackLogs) { _ in
            showMailSheet = true
        }

        .navigationTitle(Text(.settings.title))
    }
}

struct SettingsView_Previews: PreviewProvider {
    struct Container: View {
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

    static var previews: some View {
        Container()
    }
}
