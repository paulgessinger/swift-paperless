//
//  CommonPickerFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import DataModel
import Networking
import SwiftUI

struct CommonPickerFilterView: View {
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
                    Label(String(localized: .localizable(.elementIsSelected)), systemImage: "checkmark")
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
            ids.contains(id)
        case let .noneOf(ids):
            ids.contains(id)
        default:
            false
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
                    Row(String(localized: .localizable(.commonFilterAny)), selected: selection == FilterState.Filter.any) {
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
                    Picker(String(localized: .localizable(.elementSelectionMode)), selection: $mode) {
                        Text(.localizable(.includeElement)).tag(Mode.anyOf)
                        Text(.localizable(.excludeElement)).tag(Mode.noneOf)
                    }
                    .textCase(.none)
                    .padding(.bottom, 10)
                    .pickerStyle(.segmented)
                    .disabled({
                        switch selection {
                        case .any:
                            true
                        case .notAssigned:
                            true
                        case .anyOf:
                            false
                        case .noneOf:
                            false
                        }
                    }())
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color(.divider))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }

        .navigationBarTitleDisplayMode(.inline)

        .onChange(of: mode) { _, newValue in
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
    @MainActor
    static var storePath: KeyPath<DocumentStore, [UInt: Self]> { get }

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol

    static var notAssignedFilter: String { get }
    static var notAssignedPicker: String { get }
    static var singularLabel: String { get }
    static var pluralLabel: String { get }
    static var excludeLabel: String { get }

    static var icon: String { get }

    var id: UInt { get }
    var name: String { get }
}

extension Correspondent: Pickable {
    @MainActor
    static var storePath: KeyPath<DocumentStore, [UInt: Correspondent]> { \.correspondents }

    static func documentPath<D>(_: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        \.correspondent
    }

    static let notAssignedFilter = String(localized: .localizable(.correspondentNotAssignedFilter))
    static let notAssignedPicker = String(localized: .localizable(.correspondentNotAssignedPicker))
    static let singularLabel = String(localized: .localizable(.correspondent))
    static let pluralLabel = String(localized: .localizable(.correspondents))
    static let excludeLabel = String(localized: .localizable(.correspondentExclude))

    static let icon: String = "person.fill"
}

extension DocumentType: Pickable {
    @MainActor
    static var storePath: KeyPath<DocumentStore, [UInt: DocumentType]> { \.documentTypes }

    static func documentPath<D>(_: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        \.documentType
    }

    static let notAssignedFilter = String(localized: .localizable(.documentTypeNotAssignedFilter))
    static let notAssignedPicker = String(localized: .localizable(.documentTypeNotAssignedPicker))
    static let singularLabel = String(localized: .localizable(.documentType))
    static let pluralLabel = String(localized: .localizable(.documentTypes))
    static let excludeLabel = String(localized: .localizable(.documentTypeExclude))

    static let icon: String = "doc.fill"
}

extension StoragePath: Pickable {
    @MainActor
    static var storePath: KeyPath<DocumentStore, [UInt: StoragePath]> { \.storagePaths }

    static func documentPath<D>(_: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        \.storagePath
    }

    static let notAssignedFilter = String(localized: .localizable(.storagePathNotAssignedFilter))
    static let notAssignedPicker = String(localized: .localizable(.storagePathNotAssignedPicker))
    static let singularLabel = String(localized: .localizable(.storagePath))
    static let pluralLabel = String(localized: .localizable(.storagePaths))
    static let excludeLabel = String(localized: .localizable(.storagePathExclude))

    static let icon: String = "archivebox.fill"
}

struct CommonPickerEdit<Manager, D>: View
    where
    Manager: ManagerProtocol,
    Manager.Model.Element: Pickable,
    D: DocumentProtocol & Equatable
{
    typealias Element = Manager.Model.Element

    @ObservedObject var store: DocumentStore

    @EnvironmentObject var errorController: ErrorController

    @Binding var document: D

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    private var model: Manager.Model

    private var resource: UserPermissions.Resource? {
        UserPermissions.Resource(for: Element.self)
    }

    private var permissions: UserPermissions.PermissionSet {
        guard let resource else { return .empty }
        return store.permissions[resource]
    }

    private var elements: [(UInt, String)] {
        let all = model.load()
            .map { ($0.id, $0.name) }

        if searchDebounce.debouncedText.isEmpty { return all }

        return all.filter { $0.1.range(of: searchDebounce.debouncedText, options: .caseInsensitive) != nil }
    }

    init(manager _: Manager.Type, document: Binding<D>, store: DocumentStore) {
        _document = document
        self.store = store
        model = .init(store: store)
    }

    private var isSelectedVisibleToUser: Bool {
        let allDict = store[keyPath: Element.storePath]
        if let setId = document[keyPath: Element.documentPath(D.self)] {
            if allDict[setId] != nil {
                // ID is in dict, so must be visible
                return true
            } else {
                // ID is not in dict, selected ID is not visible
                return false
            }
        }
        // No ID is set, so whatever is visible is good enough
        return true
    }

    private var notVisibleIsSelectedView: some View {
        HStack {
            Text(.permissions(.private))
                .italic()
                .foregroundColor(.primary)
            Spacer()
            Label(String(localized: .localizable(.elementIsSelected)), systemImage: "checkmark")
                .labelStyle(.iconOnly)
        }
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
                Label(String(localized: .localizable(.elementIsSelected)), systemImage: "checkmark")
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

    private struct NoElementsView: View {
        var body: some View {
            ContentUnavailableView(String(localized: .localizable(.noElementsFound)),
                                   systemImage: "exclamationmark.magnifyingglass",
                                   description: Text(Element.localizedNamePlural))
        }
    }

    private struct NoPermissionsView: View {
        var body: some View {
            ContentUnavailableView(String(localized: .permissions(.noViewPermissionsDisplayTitle)),
                                   systemImage: "lock.fill",
                                   description: Text(Element.localizedNoViewPermissions))
        }
    }

    var body: some View {
        Form {
            if !permissions.test(.view) {
                NoPermissionsView()
            } else if elements.isEmpty, searchDebounce.debouncedText.isEmpty {
                NoElementsView()
            } else {
                Section {
                    row(Element.notAssignedPicker, value: nil)
                }
                Section {
                    if !isSelectedVisibleToUser {
                        notVisibleIsSelectedView
                    }
                    ForEach(elements, id: \.0) { id, name in
                        row(name, value: id)
                    }
                }
            }
        }
        .animation(.spring, value: searchDebounce.debouncedText)
        .animation(.spring, value: permissions)
        .animation(.spring, value: document)

        .searchable(text: $searchDebounce.text)

        .refreshable {
            await Task {
                do {
                    try await store.fetchAll()
                } catch {
                    errorController.push(error: error)
                }
            }.value
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    CreateView(document: $document,
                               model: model)
                } label: {
                    Label(String(localized: .localizable(.add)), systemImage: "plus")
                }
                .disabled(!permissions.test(.add))
            }
        }
        .presentationDragIndicator(.hidden)
    }
}

private struct FilterViewPreviewHelper<T: Pickable>: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository())
    @State var filterState = FilterState.Filter.any
    @State var elements: [(UInt, String)] = []

    var elementKeyPath: KeyPath<DocumentStore, [UInt: T]>

    init(elements: KeyPath<DocumentStore, [UInt: T]>) {
        elementKeyPath = elements
    }

    var body: some View {
        NavigationStack {
            CommonPickerFilterView(selection: $filterState,
                                   elements: elements)
        }
        .task {
            elements = store[keyPath: elementKeyPath]
                .map { ($0.key, $0.value.name) }
                .sorted(by: { $0.1 < $1.1 })
        }
        .environmentObject(store)
    }
}

#Preview("CommonFilterPickerCorrespondent") {
    FilterViewPreviewHelper(elements: \.correspondents)
}

#Preview("CommonFilterPickerDocumentType") {
    FilterViewPreviewHelper(elements: \.documentTypes)
}

#Preview("CommonFilterPickerStoragePaths") {
    FilterViewPreviewHelper(elements: \.storagePaths)
}
