//
//  ManageView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.23.
//

import DataModel
import Networking
import os
import SwiftUI

protocol ManagerModel: Sendable {
    associatedtype Element: Hashable, Identifiable, Sendable, LocalizedResource
    associatedtype ProtoElement: Sendable

    init(store: DocumentStore)

    @MainActor
    func load() -> [Element]

    func update(_ element: Element) async throws
    func create(_ element: ProtoElement) async throws -> Element
    func delete(_ element: Element) async throws

    @MainActor
    var permissions: UserPermissions.PermissionSet { get }
}

protocol RowViewProtocol: View {
    associatedtype Element: Sendable

    @MainActor
    init(element: Element)
}

protocol EditViewProtocol: View {
    associatedtype Element: Sendable

    @MainActor
    init(element: Element, onSave: ((Element) throws -> Void)?)
}

protocol CreateViewProtocol: View {
    associatedtype Element: Sendable

    @MainActor
    init(onSave: @escaping (Element) throws -> Void)
}

protocol ManagerProtocol {
    associatedtype Model: ManagerModel
    associatedtype RowView: RowViewProtocol where RowView.Element == Model.Element
    associatedtype EditView: EditViewProtocol where EditView.Element == Model.Element
    associatedtype CreateView: CreateViewProtocol where CreateView.Element == Model.ProtoElement

    static var elementName: KeyPath<Model.Element, String> { get }
}

struct ManageView<Manager>: View where Manager: ManagerProtocol {
    typealias Element = Manager.Model.Element

    @EnvironmentObject var errorController: ErrorController
    @EnvironmentObject var store: DocumentStore

    @State var model: Manager.Model?

    @State private var elements: [Element] = []

    @State private var searchText = ""

    struct Edit: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var errorController: ErrorController
        var model: Manager.Model

        var element: Element

        private var onSave: ((Element) throws -> Void)? {
            guard model.permissions.test(.change) else {
                return nil
            }
            return { newElement in
                Task {
                    do {
                        try await model.update(newElement)
                        dismiss()
                    } catch {
                        print(error)
                        errorController.push(error: error)
                    }
                }
            }
        }

        var body: some View {
            Manager.EditView(element: element, onSave: onSave)
        }
    }

    struct Create: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var errorController: ErrorController
        var model: Manager.Model

        var onSave: () -> Void

        var body: some View {
            Manager.CreateView(onSave: { newElement in
                Task {
                    do {
                        _ = try await model.create(newElement)
                        onSave()
                        dismiss()
                    } catch {
                        errorController.push(error: error)
                        throw error
                    }
                }

            })
        }
    }

    func filter(element: Element) -> Bool {
        if searchText.isEmpty { return true }
        if let _ = element[keyPath: Manager.elementName].range(of: searchText, options: .caseInsensitive) {
            return true
        } else {
            return false
        }
    }

    private func refresh() async {
        do {
            try await store.fetchAll()
            if let model {
                withAnimation {
                    elements = model.load()
                }
            }
        } catch {
            errorController.push(error: error)
        }
    }

    private var noElementsView: some View {
        ContentUnavailableView(String(localized: .localizable(.noElementsFound)),
                               systemImage: "exclamationmark.magnifyingglass",
                               description: Text(Element.localizedNamePlural))
    }

    private var noPermissionsView: some View {
        ContentUnavailableView(String(localized: .permissions(.noViewPermissionsDisplayTitle)),
                               systemImage: "lock.fill",
                               description: Text(Element.localizedNoViewPermissions))
    }

    private func test(_ operation: UserPermissions.Operation) -> Bool {
        model?.permissions.test(operation) ?? false
    }

    private var permissions: UserPermissions.PermissionSet {
        model?.permissions ?? .empty
    }

    private func deleteRow(at offsets: IndexSet) {
        for (i, element) in elements.enumerated() {
            guard offsets.contains(i) else { continue }
            Task {
                do {
                    try await model?.delete(element)
                } catch {
                    Logger.shared.error("Error deleting element: \(error)")
                    errorController.push(error: error)
                }
            }
        }
        elements.remove(atOffsets: offsets)
    }

    var body: some View {
        let displayElements = elements.filter { filter(element: $0) }
        List {
            if let model {
                if !model.permissions.test(.view) {
                    noPermissionsView
                } else if elements.isEmpty, searchText.isEmpty {
                    noElementsView
                } else {
                    if !displayElements.isEmpty {
                        ForEach(displayElements, id: \.self) { element in
                            NavigationLink {
                                Edit(model: model, element: element)
                            } label: {
                                Manager.RowView(element: element)
                            }
                        }
                        .if(test(.delete)) {
                            $0.onDelete(perform: deleteRow)
                        }
                    }
                }
            }
        }
        .animation(.spring, value: displayElements)
        .animation(.spring, value: permissions)
        .searchable(text: $searchText)

        .navigationBarTitleDisplayMode(.inline)

        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                NavigationLink {
                    if let model {
                        Create(model: model) {
                            Task {
                                await refresh()
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(String(localized: .localizable(.add)))
                }
                .disabled(!test(.add))

                EditButton()
                    .disabled(!test(.change))
            }
        }

        .refreshable {
            await Task { await refresh() }.value
        }

        .task {
            if model == nil {
                model = Manager.Model(store: store)
                elements = model!.load()
            }
        }
    }
}

private struct Container<M: ManagerProtocol>: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository())
    @StateObject var errorController = ErrorController()

    var body: some View {
        NavigationStack {
            ManageView<M>()
        }
        .environmentObject(store)
        .errorOverlay(errorController: errorController)
    }
}

struct TagManageView_Previews: PreviewProvider {
    static var previews: some View {
        Container<TagManager>()
    }
}

struct CorrespondentManageView_Previews: PreviewProvider {
    static var previews: some View {
        Container<CorrespondentManager>()
    }
}
