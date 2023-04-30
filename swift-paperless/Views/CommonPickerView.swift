//
//  CommonPickerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct CommonPicker: View {
    @Binding var selection: FilterState.Filter
    var elements: [(UInt, String)]

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    func row(_ label: String, value: FilterState.Filter) -> some View {
        return HStack {
            Button(action: { Task { selection = value } }) {
                Text(label)
            }
            .foregroundColor(.primary)
            Spacer()
            if selection == value {
                Label("Active", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func filter(name: String) -> Bool {
        if searchDebounce.debouncedText.isEmpty { return true }
        if let _ = name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) {
            return true
        } else {
            return false
        }
    }

    var body: some View {
        VStack {
            SearchBarView(text: $searchDebounce.text)
                .transition(.opacity)
                .padding(.horizontal)
                .padding(.vertical, 2)
            Form {
                Section {
                    row("Any", value: FilterState.Filter.any)
                }
                Section {
                    ForEach(elements.filter { filter(name: $0.1) },
                            id: \.0)
                    { id, name in
                        row(name, value: FilterState.Filter.only(id: id))
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color("Divider"))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }
    }
}

protocol Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Self]> { get }
    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol

    var id: UInt { get }
    var name: String { get }
}

extension Correspondent: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Correspondent]> { \.correspondents }

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.correspondent
    }
}

extension DocumentType: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: DocumentType]> { \.documentTypes }

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.documentType
    }
}

struct CommonPickerEdit<Manager, D>: View
    where
    Manager: ManagerProtocol,
    Manager.Model.Element: Pickable,
//    Manager.CreateView.Element: Pickable,
    D: DocumentProtocol
{
    typealias Element = Manager.Model.Element

    @ObservedObject var store: DocumentStore

    @Binding var document: D

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    @State private var showNone = true

    private var model: Manager.Model

    private func elements() -> [(UInt, String)] {
        let allDict = store[keyPath: Element.storePath]

        let all = allDict.sorted {
            $0.value.name < $1.value.name
        }.map { ($0.value.id, $0.value.name) }

        if searchDebounce.debouncedText.isEmpty { return all }

        return all.filter { $0.1.range(of: searchDebounce.debouncedText, options: .caseInsensitive) != nil }
    }

    init(manager: Manager.Type, document: Binding<D>, store: DocumentStore) {
        self._document = document
        self.store = store
        self.model = .init(store: store)
    }

    private func row(_ label: String, value: UInt?) -> some View {
        return HStack {
            Button(action: {
                // set new value
                document[keyPath: Element.documentPath(D.self)] = value
            }) {
                Text(label)
            }
            .foregroundColor(.primary)
            Spacer()
            if document[keyPath: Element.documentPath(D.self)] == value {
                Label("Active", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private struct CreateView: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var errorController: ErrorController

        @Binding var document: D
        var model: Manager.Model

        var body: some View {
            Manager.CreateView(onSave: { newElement in
                Task {
                    do {
                        let created = try await model.create(newElement)
                        document[keyPath: Element.documentPath(D.self)] = created.id
                        dismiss()
                    } catch {
                        errorController.push(error: error)
                        throw error
                    }
                }

            })
        }
    }

    var body: some View {
        VStack {
            SearchBarView(text: $searchDebounce.text)
                .transition(.opacity)
                .padding(.horizontal)
                .padding(.vertical, 2)
            Form {
                if showNone {
                    Section {
                        row("None", value: nil)
                    }
                }
                Section {
                    ForEach(elements(), id: \.0) { id, name in
                        row(name, value: id)
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color("Divider"))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }
        .onChange(of: searchDebounce.debouncedText) { value in
            withAnimation {
                showNone = value.isEmpty
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    CreateView(document: $document,
                               model: model)
                } label: {
                    Label("Add new", systemImage: "plus")
                }
            }
        }
    }
}

struct CommonPickerEditCorrespondent_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        DocumentLoader(id: 1) { document in
            NavigationStack {
                CommonPickerEdit(
                    manager: CorrespondentManager.self,
                    document: document,
                    store: store
                )
            }
        }
        .environmentObject(store)
    }
}

struct CommonPickerEditDocumentType_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        DocumentLoader(id: 1) { document in
            NavigationStack {
                CommonPickerEdit(
                    manager: DocumentTypeManager.self,
                    document: document,
                    store: store
                )
            }
        }
        .environmentObject(store)
    }
}
