//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import SwiftUI
import SwiftUINavigation

// MARK: - Tag Management

extension TagView: RowViewProtocol {
    typealias Element = Tag
    init(element: Tag) {
        self.init(tag: element)
    }
}

extension TagEditView: EditViewProtocol where Element == Tag {
    init(element: Tag, onSave: @escaping (Element) throws -> Void) {
        self.init(tag: element, onSave: onSave)
    }
}

extension TagEditView: CreateViewProtocol where Element == ProtoTag {}

struct TagManager: ManagerProtocol {
    final class Model: ManagerModel {
        typealias Element = Tag
        typealias ProtoElement = ProtoTag

        @Published var searchText: String = ""

        private var store: DocumentStore

        init(store: DocumentStore) {
            self.store = store
        }

        func load() -> [Element] {
            return store.tags
                .map { $0.value }
                .sorted(by: { $0.name < $1.name })
        }

        func update(_ tag: Tag) async throws {
            try await store.updateTag(tag)
        }

        func create(_ tag: ProtoTag) async throws {
            _ = try await store.createTag(tag)
        }

        func delete(_ tag: Tag) async throws {
            try await store.deleteTag(tag)
        }

        func filter(element tag: Tag) -> Bool {
            if searchText.isEmpty { return true }
            if let _ = tag.name.range(of: searchText, options: .caseInsensitive) {
                return true
            } else {
                return false
            }
        }
    }

    typealias RowView = TagView
    typealias EditView = TagEditView<Tag>
    typealias CreateView = TagEditView<ProtoTag>
}

// MARK: - Correspondent Management

// MARK: - Document Management

// MARK: - Saved View Management ?

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        List {
            NavigationLink {
                ManageView<TagManager>(store: store)
                    .navigationTitle("Tags")
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
