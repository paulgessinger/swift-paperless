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
        _selection = selection
        self.elements = elements
        self.notAssignedLabel = notAssignedLabel

        switch self.selection {
        case .any, .anyOf, .notAssigned:
            _mode = State(initialValue: .anyOf)
        case .noneOf:
            _mode = State(initialValue: .noneOf)
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
                    Label("Element is selected", systemImage: "checkmark")
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
        case let .anyOf(ids):
            return ids.contains(id)
        case let .noneOf(ids):
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
                    Row(String(localized: "Any"), selected: selection == FilterState.Filter.any) {
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
                            case var .anyOf(ids):
                                if ids.contains(id) {
                                    ids = ids.filter { $0 != id }
                                    selection = ids.isEmpty ? .any : .anyOf(ids: ids)
                                } else {
                                    selection = .anyOf(ids: [id] + ids)
                                }
                            case var .noneOf(ids):
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
                    Picker(String(localized: "Selection mode", comment: "Common element selection mode (include/exclude)"), selection: $mode) {
                        Text("Include element").tag(Mode.anyOf)
                        Text("Exclude element").tag(Mode.noneOf)
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
                case let .noneOf(ids):
                    selection = .anyOf(ids: ids)
                case .anyOf:
                    // noop
                    break
                default:
                    preconditionFailure("Changed CommonPicker selection mode, but was not in either of the modes")
                }
            case .noneOf:
                switch selection {
                case let .anyOf(ids):
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

    static var notAssignedFilter: String { get }
    static var notAssignedPicker: String { get }
    static var singularLabel: String { get }
    static var pluralLabel: String { get }
    static var excludeLabel: String { get }

    var id: UInt { get }
    var name: String { get }
}

extension Correspondent: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Correspondent]> = \.correspondents

    static func documentPath<D>(_: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        \.correspondent
    }

    static var notAssignedFilter = String(localized: .localizable.correspondentNotAssignedFilter)
    static var notAssignedPicker = String(localized: .localizable.correspondentNotAssignedPicker)
    static var singularLabel = String(localized: "Correspondent")
    static var pluralLabel = String(localized: "Correspondents")
    static var excludeLabel = String(localized: "Exclude correspondent")
}

extension DocumentType: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: DocumentType]> = \.documentTypes

    static func documentPath<D>(_: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        \.documentType
    }

    static var notAssignedFilter = LocalizedStrings.Filter.DocumentType.notAssignedFilter
    static var notAssignedPicker = LocalizedStrings.Filter.DocumentType.notAssignedPicker
    static var singularLabel = String(localized: "Document type")
    static var pluralLabel = String(localized: "Document types")
    static var excludeLabel = String(localized: "Exclude document type")
}

extension StoragePath: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: StoragePath]> = \.storagePaths

    static func documentPath<D>(_: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        \.storagePath
    }

    static var notAssignedFilter = LocalizedStrings.Filter.StoragePath.notAssignedFilter
    static var notAssignedPicker = LocalizedStrings.Filter.StoragePath.notAssignedPicker
    static var singularLabel = String(localized: "Storage path")
    static var pluralLabel = String(localized: "Storage paths")
    static var excludeLabel = String(localized: "Exclude storage path")
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

    init(manager _: Manager.Type, document: Binding<D>, store: DocumentStore) {
        _document = document
        self.store = store
        model = .init(store: store)
    }

    private func row(_ label: String, value: UInt?) -> some View {
        HStack {
            Button(action: {
                // set new value
                document[keyPath: Element.documentPath(D.self)] = value
            }) {
                Text(label)
            }
            .foregroundColor(.primary)
            Spacer()
            if document[keyPath: Element.documentPath(D.self)] == value {
                Label("Element is selected", systemImage: "checkmark")
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
                        row(Element.notAssignedPicker, value: nil)
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
                    Label("Add", systemImage: "plus")
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
        elementKeyPath = elements
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
