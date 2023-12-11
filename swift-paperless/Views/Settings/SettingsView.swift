//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import SwiftUI
import SwiftUINavigation

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var connectionManager: ConnectionManager

    @State var extraHeaders: [ConnectionManager.HeaderValue] = []

    var body: some View {
        List {
            Section(String(localized: .settings.activeServer)) {
                Text(connectionManager.apiHost ?? "No server")
            }
            Section(String(localized: .settings.organization)) {
                NavigationLink {
                    ManageView<TagManager>(store: store)
                        .navigationTitle(Text(.localizable.tags))
                        .task { Task.detached { await store.fetchAllTags() }}
                } label: {
                    Label(String(localized: .localizable.tags), systemImage: "tag.fill")
                }

                NavigationLink {
                    ManageView<CorrespondentManager>(store: store)
                        .navigationTitle(Text(.localizable.correspondents))
                        .task { Task.detached { await store.fetchAllCorrespondents() }}
                } label: {
                    Label(String(localized: .localizable.correspondents), systemImage: "person.fill")
                }

                NavigationLink {
                    ManageView<DocumentTypeManager>(store: store)
                        .navigationTitle(Text(.localizable.documentTypes))
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label(String(localized: .localizable.documentTypes), systemImage: "doc.fill")
                }

                NavigationLink {
                    ManageView<SavedViewManager>(store: store)
                        .navigationTitle(Text(.localizable.savedViews))
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label(String(localized: .localizable.savedViews), systemImage: "line.3.horizontal.decrease.circle.fill")
                }

                NavigationLink {
                    ManageView<StoragePathManager>(store: store)
                        .navigationTitle(Text(.localizable.storagePaths))
                        .task { Task.detached { await store.fetchAllStoragePaths() }}
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

                Button {
                    UIApplication.shared.open(URL(string: "mailto:swift-paperless@paulgessinger.com")!)
                } label: {
                    Label(String(localized: .settings.detailsFeedback), systemImage: "paperplane.fill")
                        .accentColor(.primary)
                }
            }
        }

        .task {
            extraHeaders = connectionManager.extraHeaders
        }

        .onChange(of: extraHeaders) { value in
            connectionManager.extraHeaders = value
            store.set(repository: ApiRepository(connection: connectionManager.connection!))
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
