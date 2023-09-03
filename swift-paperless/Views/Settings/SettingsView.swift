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
            Section("Organization") {
                NavigationLink {
                    ManageView<TagManager>(store: store)
                        .navigationTitle("Tags")
                        .task { Task.detached { await store.fetchAllTags() }}
                } label: {
                    Label("Tags", systemImage: "tag.fill")
                }

                NavigationLink {
                    ManageView<CorrespondentManager>(store: store)
                        .navigationTitle("Correspondents")
                        .task { Task.detached { await store.fetchAllCorrespondents() }}
                } label: {
                    Label("Correspondents", systemImage: "person.fill")
                }

                NavigationLink {
                    ManageView<DocumentTypeManager>(store: store)
                        .navigationTitle("Document types")
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label("Document types", systemImage: "doc.fill")
                }

                NavigationLink {
                    ManageView<SavedViewManager>(store: store)
                        .navigationTitle("Saved views")
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label("Saved views", systemImage: "line.3.horizontal.decrease.circle.fill")
                }

                NavigationLink {
                    ManageView<StoragePathManager>(store: store)
                        .navigationTitle("Storage paths")
                        .task { Task.detached { await store.fetchAllStoragePaths() }}
                } label: {
                    Label("Storage paths", systemImage: "archivebox.fill")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    PreferencesView()
                        .navigationTitle("Preferences")
                } label: {
                    Label("Preferences", systemImage: "dial.low.fill")
                }
            }

            Section("Advanced") {
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Label("Extra headers", systemImage: "list.bullet.rectangle.fill")
                }
            }

            Section("Details") {
                NavigationLink {
                    LibrariesView()
                } label: {
                    Label("Libraries", systemImage: "books.vertical.fill")
                }

                Button {
                    UIApplication.shared.open(URL(string: "https://github.com/paulgessinger/swift-paperless/")!)
                } label: {
                    Label("Source code", systemImage: "terminal.fill")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("Privacy", systemImage: "hand.raised.fill")
                }

                Button {
                    UIApplication.shared.open(URL(string: "mailto:swift-paperless@paulgessinger.com")!)
                } label: {
                    Label("Feedback", systemImage: "paperplane.fill")
                }
                .buttonStyle(.plain)
            }
        }

        .task {
            extraHeaders = connectionManager.extraHeaders
        }

        .onChange(of: extraHeaders) { value in
            connectionManager.extraHeaders = value
            store.set(repository: ApiRepository(connection: connectionManager.connection!))
        }

        .navigationTitle("Settings")
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
