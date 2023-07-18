//
//  SwiftUIView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.23.
//

import SwiftUI

protocol ManagerModel {
    associatedtype Element: Hashable, Identifiable
    associatedtype ProtoElement

    init(store: DocumentStore)

    func load() -> [Element]
    func update(_ element: Element) async throws
    func create(_ element: ProtoElement) async throws -> Element
    func delete(_ element: Element) async throws
}

protocol RowViewProtocol: View {
    associatedtype Element
    init(element: Element)
}

protocol EditViewProtocol: View {
    associatedtype Element
    init(element: Element, onSave: @escaping (Element) throws -> Void)
}

protocol CreateViewProtocol: View {
    associatedtype Element
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

    var model: Manager.Model
    @State private var elementToDelete: Element?
    @State private var elements: [Element] = []

    @State private var searchText: String = ""

    init(store: DocumentStore) {
        self.model = .init(store: store)
    }

    struct Edit: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var errorController: ErrorController
        var model: Manager.Model

        var element: Element

        var body: some View {
            Manager.EditView(element: element, onSave: { newElement in
                Task {
                    do {
                        try await model.update(newElement)
                        dismiss()
                    } catch {
                        print(error)
                        errorController.push(error: error)
                    }
                }

            })
        }
    }

    struct Create: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var errorController: ErrorController
        var model: Manager.Model

        var body: some View {
            Manager.CreateView(onSave: { newElement in
                Task {
                    do {
                        _ = try await model.create(newElement)
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

    var body: some View {
        VStack {
            if elements.isEmpty {
                Divider()
                Text("no_elements_found")
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                SearchBarView(text: $searchText, cancelEnabled: true)
                    .padding(.horizontal)
                    .padding(.bottom, 3)
                List {
                    ForEach(elements.filter(filter), id: \.self) { element in
                        NavigationLink {
                            Edit(model: model, element: element)
                        } label: {
                            Manager.RowView(element: element)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                elements.removeAll(where: { $0 == element })
                                elementToDelete = element
                            }
                        }
                    }
                    .onDelete { _ in }
                }
            }
        }

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    Create(model: model)
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }

        .confirmationDialog(String(localized: "Are you sure?", comment: "Common element delete confirmation"),
                            isPresented: $elementToDelete.isPresent(),
                            titleVisibility: .visible)
        {
            Button("Delete", role: .destructive) {
                let e = elementToDelete!
                Task {
                    do {
                        try await model.delete(e)
                        elementToDelete = nil
                    } catch {
                        print(error)
                        errorController.push(error: error)
                        elements = model.load()
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                withAnimation {
                    elements = model.load()
                }
            }
        }

        .refreshable {
            await store.fetchAll()
            withAnimation {
                elements = model.load()
            }
        }

        .task {
            elements = model.load()
        }
    }
}

private struct Container<M: ManagerProtocol>: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository())
    @StateObject var errorController = ErrorController()

    var body: some View {
        NavigationStack {
            ManageView<M>(store: store)
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
