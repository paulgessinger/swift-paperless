//
//  SwiftUIView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.23.
//

import SwiftUI

protocol ManagerModel: ObservableObject {
    associatedtype Element: Hashable, Identifiable
    associatedtype ProtoElement

    var searchText: String { get set }

    init(store: DocumentStore)

    func load() -> [Element]
    func update(_ element: Element) async throws
    func create(_ element: ProtoElement) async throws
    func delete(_ element: Element) async throws

    func filter(element: Element) -> Bool
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
}


struct ManageView<Manager>: View where Manager: ManagerProtocol {
    typealias Element = Manager.Model.Element

    @EnvironmentObject var errorController: ErrorController

    @ObservedObject var model: Manager.Model
    @State private var elementToDelete: Element?
    @State private var elements: [Element] = []

    init(store: DocumentStore) {
        self.model = .init(store: store)
    }

    struct Edit: View {
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject var errorController: ErrorController
        @ObservedObject var model: Manager.Model

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
        @ObservedObject var model: Manager.Model

        var body: some View {
            Manager.CreateView(onSave: { newTag in
                Task {
                    do {
                        try await model.create(newTag)
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
            SearchBarView(text: $model.searchText, cancelEnabled: true)
                .padding(.horizontal)
                .padding(.bottom, 3)
            List {
                ForEach(elements.filter(model.filter), id: \.self) { element in
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

        .confirmationDialog("Are you sure?",
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
            withAnimation {
                elements = model.load()
            }
        }
//        .searchable(text: $model.searchText)

        .task {
            elements = model.load()
        }
    }
}

struct ManageView_Previews: PreviewProvider {
    struct Container: View {
        @StateObject var store = DocumentStore(repository: PreviewRepository())
        @StateObject var errorController = ErrorController()

        var body: some View {
            NavigationStack {
                ManageView<TagManager>(store: store)
            }
            .environmentObject(store)
            .errorOverlay(errorController: errorController)
        }
    }

    static var previews: some View {
        Container()
    }
}
