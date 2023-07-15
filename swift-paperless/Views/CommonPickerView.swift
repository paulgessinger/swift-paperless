//
//  CommonPickerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct CommonPicker: View {
    private enum Mode {
        case anyOf
        case noneOf
    }

    @State private var mode: Mode = .anyOf
    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    @Binding var selection: FilterState.Filter
    var elements: [(UInt, String)]
    var notAssignedLabel: String

    init(selection: Binding<FilterState.Filter>, elements: [(UInt, String)], notAssignedLabel: String = "Not assigned") {
        self._selection = selection
        self.elements = elements
        self.notAssignedLabel = notAssignedLabel

        switch self.selection {
        case .any, .anyOf, .notAssigned:
            self._mode = State(initialValue: .anyOf)
        case .noneOf:
            self._mode = State(initialValue: .noneOf)
        }
    }

    private struct Row: View {
        let label: String
        let selected: Bool
        let action: () -> Void

        init(_ label: String, selected: Bool, action: @escaping () -> Void = {}) {
            self.label = label
            self.selected = selected
            self.action = action
        }

        var body: some View {
            HStack {
                Button(action: action) {
                    Text(label)
                }
                .foregroundColor(.primary)
                Spacer()
                if selected {
                    Label("Active", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                }
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

    private func selected(id: UInt) -> Bool {
        switch selection {
        case .anyOf(let ids):
            return ids.contains(id)
        case .noneOf(let ids):
            return ids.contains(id)
        default:
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
                    Row("Any", selected: selection == FilterState.Filter.any) {
                        selection = .any
                    }
                    Row(notAssignedLabel, selected: selection == FilterState.Filter.notAssigned) {
                        selection = .notAssigned
                    }
                }
                Section {
                    ForEach(elements.filter { filter(name: $0.1) },
                            id: \.0)
                    { id, name in
                        Row(name, selected: selected(id: id)) {
                            switch selection {
                            case .any:
                                selection = .anyOf(ids: [id])
                            case .notAssigned:
                                selection = .anyOf(ids: [id])
                            case .anyOf(var ids):
                                if ids.contains(id) {
                                    ids = ids.filter { $0 != id }
                                    selection = ids.isEmpty ? .any : .anyOf(ids: ids)
                                } else {
                                    selection = .anyOf(ids: [id] + ids)
                                }
                            case .noneOf(var ids):
                                if ids.contains(id) {
                                    ids = ids.filter { $0 != id }
                                    selection = ids.isEmpty ? .any : .noneOf(ids: ids)
                                } else {
                                    selection = .noneOf(ids: [id] + ids)
                                }
                            }
                        }
                    }
                } header: {
                    Picker("Mode", selection: $mode) {
                        Text("Include").tag(Mode.anyOf)
                        Text("Exclude").tag(Mode.noneOf)
                    }
                    .textCase(.none)
                    .padding(.bottom, 10)
                    .pickerStyle(.segmented)
                    .disabled({
                        switch selection {
                        case .any:
                            return true
                        case .notAssigned:
                            return true
                        case .anyOf:
                            return false
                        case .noneOf:
                            return false
                        }
                    }())
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color("Divider"))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }

        .onChange(of: mode) { newValue in
            switch newValue {
            case .anyOf:
                switch selection {
                case .noneOf(let ids):
                    selection = .anyOf(ids: ids)
                case .anyOf:
                    // noop
                    break
                default:
                    preconditionFailure("Changed CommonPicker selection mode, but was not in either of the modes")
                }
            case .noneOf:
                switch selection {
                case .anyOf(let ids):
                    selection = .noneOf(ids: ids)
                case .noneOf:
                    // noop
                    break
                default:
                    preconditionFailure("Changed mode, but was not in either of the modes")
                }
            }
        }
    }
}

protocol Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Self]> { get }
    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol

    static var notAssignedLabel: String { get }
    static var singularLabel: String { get }
    static var pluralLabel: String { get }

    var id: UInt { get }
    var name: String { get }
}

extension Correspondent: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Correspondent]> = \.correspondents

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.correspondent
    }

    static var notAssignedLabel = "None"
    static var singularLabel = "Correspondent"
    static var pluralLabel = "Correspondents"
}

extension DocumentType: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: DocumentType]> = \.documentTypes

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.documentType
    }

    static var notAssignedLabel: String = "None"
    static var singularLabel = "Document Type"
    static var pluralLabel = "Document Types"
}

extension StoragePath: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: StoragePath]> = \.storagePaths

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.storagePath
    }

    static var notAssignedLabel: String = "Default"
    static var singularLabel = "Storage Path"
    static var pluralLabel = "Storage Paths"
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
                        row(Element.notAssignedLabel, value: nil)
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

private struct FilterViewPreviewHelper<T: Pickable>: View {
    @EnvironmentObject var store: DocumentStore
    @State var filterState = FilterState.Filter.any
    @State var elements: [(UInt, String)] = []

    var elementKeyPath: KeyPath<DocumentStore, [UInt: T]>

    init(elements: KeyPath<DocumentStore, [UInt: T]>) {
        self.elementKeyPath = elements
    }

    var body: some View {
        NavigationStack {
            CommonPicker(selection: $filterState,
                         elements: elements)
        }
        .task {
            elements = store[keyPath: elementKeyPath]
                .map { ($0.key, $0.value.name) }
                .sorted(by: { $0.1 < $1.1 })
        }
    }
}

struct CommonFilterPickerCorrespondent_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        FilterViewPreviewHelper(elements: \.correspondents)
            .environmentObject(store)
    }
}

struct CommonFilterPickerDocumentType_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        FilterViewPreviewHelper(elements: \.documentTypes)
            .environmentObject(store)
    }
}

struct CommonFilterPickerStoragePaths_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        FilterViewPreviewHelper(elements: \.storagePaths)
            .environmentObject(store)
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

struct CommonPickerEditStoragePath_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        DocumentLoader(id: 1) { document in
            NavigationStack {
                CommonPickerEdit(
                    manager: StoragePathManager.self,
                    document: document,
                    store: store
                )
            }
        }
        .environmentObject(store)
    }
}
