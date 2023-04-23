//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import SwiftUI
import SwiftUINavigation

struct TagManageView: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var errorController: ErrorController

    struct SingleTag: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var store: DocumentStore
        @EnvironmentObject var errorController: ErrorController

        var tag: Tag

        var body: some View {
            TagEditView(tag: tag, onSave: { newTag in
                Task {
                    do {
                        try await store.updateTag(newTag)
                        dismiss()
                    } catch {
                        print(error)
                        errorController.push(error: error)
                    }
                }

            })
        }
    }

    private struct CreateTag: View {
        @EnvironmentObject private var store: DocumentStore
        @EnvironmentObject private var errorController: ErrorController
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            TagEditView<ProtoTag>(onSave: { value in
                Task {
                    do {
                        _ = try await store.createTag(value)
                        dismiss()
                    } catch {
                        errorController.push(error: error)
                        throw error
                    }
                }
            })
        }
    }

    @State private var tags: [Tag] = []
    @State private var tagToDelete: Tag?
    @State private var searchText = ""

    func loadTags() {
        tags = store.tags
            .map { $0.value }
            .sorted(by: { $0.name < $1.name })
    }

    private func tagFilter(tag: Tag) -> Bool {
        if searchText.isEmpty { return true }
        if let _ = tag.name.range(of: searchText, options: .caseInsensitive) {
            return true
        } else {
            return false
        }
    }

    var body: some View {
        VStack {
            SearchBarView(text: $searchText, cancelEnabled: true)
                .padding(.horizontal)
                .padding(.bottom, 3)
            List {
                ForEach(tags.filter(tagFilter), id: \.self) { tag in
                    NavigationLink {
                        SingleTag(tag: tag)
                    } label: {
                        TagView(tag: tag)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            tags.removeAll(where: { $0 == tag })
                            tagToDelete = tag
                        }
                    }
                }
                .onDelete { _ in }
            }
        }

        .confirmationDialog("Are you sure?",
                            isPresented: $tagToDelete.isPresent(),
                            titleVisibility: .visible)
        {
            Button("Delete", role: .destructive) {
                let t = tagToDelete!
                Task {
                    do {
                        try await store.deleteTag(t)
                        tagToDelete = nil
                    } catch {
                        print(error)
                        errorController.push(error: error)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                withAnimation {
                    loadTags()
                }
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    CreateTag()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }

        .navigationTitle("Tags")

        .refreshable {
            await store.fetchAllTags()
        }

        .task {
            loadTags()
        }

        .onChange(of: store.tags) { _ in
            loadTags()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        List {
            NavigationLink {
                TagManageView()
            } label: {
                Label("Tags", systemImage: "tag.fill")
            }
        }
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    struct Container: View {
        @StateObject var store = DocumentStore(repository: PreviewRepository())

        @StateObject var errorController = ErrorController()

        var body: some View {
            NavigationStack {
                SettingsView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(store)
            .errorOverlay(errorController: errorController)
        }
    }

    static var previews: some View {
        Container()
    }
}
