//
//  ManageView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.23.
//

import DataModel
import Networking
import SwiftUI
import os

public struct HierarchyNode<Element: Hashable & Identifiable & Sendable>: Hashable, Identifiable,
  Sendable
{
  public var element: Element
  public var children: [HierarchyNode<Element>]?

  public var id: Element.ID { element.id }
}

public protocol ManagerModel: Sendable {
  associatedtype Element: Hashable, Identifiable, Sendable, LocalizedResource
  associatedtype ProtoElement: Sendable

  init(store: DocumentStore)

  @MainActor
  func load() -> [Element]

  /// Optional hierarchical view of `load()`. Return `nil` for a flat list.
  /// When non-nil, `ManageView` renders an outline; the flattened set must
  /// match `load()` so search and delete keep working.
  @MainActor
  func hierarchy() -> [HierarchyNode<Element>]?

  func update(_ element: Element) async throws
  func create(_ element: ProtoElement) async throws -> Element
  func delete(_ element: Element) async throws

  @MainActor
  var permissions: UserPermissions.PermissionSet { get }
}

extension ManagerModel {
  @MainActor
  public func hierarchy() -> [HierarchyNode<Element>]? { nil }
}

public protocol RowViewProtocol: View {
  associatedtype Element: Sendable

  @MainActor
  init(element: Element)
}

public protocol EditViewProtocol: View {
  associatedtype Element: Sendable

  @MainActor
  init(element: Element, onSave: ((Element) throws -> Void)?)
}

public protocol CreateViewProtocol: View {
  associatedtype Element: Sendable

  @MainActor
  init(onSave: @escaping (Element) throws -> Void)
}

public protocol ManagerProtocol {
  associatedtype Model: ManagerModel
  associatedtype RowView: RowViewProtocol where RowView.Element == Model.Element
  associatedtype EditView: EditViewProtocol where EditView.Element == Model.Element
  associatedtype CreateView: CreateViewProtocol where CreateView.Element == Model.ProtoElement

  static var elementName: KeyPath<Model.Element, String> { get }
}

public struct ManageView<Manager>: View where Manager: ManagerProtocol {
  public typealias Element = Manager.Model.Element

  @EnvironmentObject public var errorController: ErrorController
  @EnvironmentObject public var store: DocumentStore
  @Environment(\.editMode) private var editMode

  @State public var model: Manager.Model?

  @State private var elements: [Element] = []
  @State private var hierarchy: [HierarchyNode<Element>]? = nil

  @State private var searchText = ""

  public init() {}

  public struct Edit: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var errorController: ErrorController
    var model: Manager.Model

    var element: Element

    var onSave: ((Element) async throws -> Void)

    private func onSaveInternal(_ element: Element) throws {
      Task {
        do {
          try await onSave(element)
          dismiss()
        } catch {
          Logger.shared.error("Failed to save \(Element.self): \(error)")
          errorController.push(error: error)
        }
      }
    }

    public var body: some View {
      Manager.EditView(element: element, onSave: onSaveInternal)
        .disabled(!model.permissions.test(.change))
    }
  }

  public struct Create: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var errorController: ErrorController
    var model: Manager.Model

    var onSave: () -> Void

    public var body: some View {
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

  public func filter(element: Element) -> Bool {
    if searchText.isEmpty { return true }
    if element[keyPath: Manager.elementName].range(of: searchText, options: .caseInsensitive) != nil
    {
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
          hierarchy = model.hierarchy()
        }
      }
    } catch {
      errorController.push(error: error)
    }
  }

  private var noElementsView: some View {
    ContentUnavailableView(
      String(localized: .app(.noElementsFound)),
      systemImage: "exclamationmark.magnifyingglass",
      description: Text(Element.localizedNamePlural))
  }

  private var noPermissionsView: some View {
    ContentUnavailableView(
      String(localized: .permissions(.noViewPermissionsDisplayTitle)),
      systemImage: "lock.fill",
      description: Text(Element.localizedNoViewPermissions))
  }

  private func test(_ operation: UserPermissions.Operation) -> Bool {
    model?.permissions.test(operation) ?? false
  }

  private var permissions: UserPermissions.PermissionSet {
    model?.permissions ?? .empty
  }

  private func reloadElements() {
    guard let model else { return }
    elements = model.load()
    hierarchy = model.hierarchy()
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
    hierarchy = model?.hierarchy()
  }

  @ViewBuilder
  private func elementLink(
    _ element: Element, model: Manager.Model, swipeDelete: Bool = false
  ) -> some View {
    NavigationLink {
      Edit(model: model, element: element) { element in
        guard model.permissions.test(.change) else {
          Logger.shared.info(
            "Silently not saving from edit view: this likely indicates a button is active that shouldn't be"
          )
          return
        }

        try await model.update(element)

        // The store is the source of truth, including any side effects on
        // other elements (e.g. parent reassignments). Reload everything
        // so the hierarchy and rows stay in sync.
        await MainActor.run { reloadElements() }
      }
    } label: {
      Manager.RowView(element: element)
    }
    .swipeActions(edge: .trailing) {
      if swipeDelete && test(.delete) {
        Button(role: .destructive) {
          Task {
            do {
              try await model.delete(element)
              await MainActor.run { reloadElements() }
            } catch {
              Logger.shared.error("Error deleting element: \(error)")
              errorController.push(error: error)
            }
          }
        } label: {
          Label(String(localized: .app(.delete)), systemImage: "trash")
        }
      }
    }
  }

  public var body: some View {
    let displayElements = elements.filter { filter(element: $0) }
    let useHierarchy = hierarchy != nil && searchText.isEmpty
    List {
      if let model {
        if !model.permissions.test(.view) {
          noPermissionsView
        } else if elements.isEmpty, searchText.isEmpty {
          noElementsView
        } else if useHierarchy, let hierarchy {
          OutlineGroup(hierarchy, children: \.children) { node in
            elementLink(node.element, model: model, swipeDelete: true)
          }
        } else {
          if !displayElements.isEmpty {
            ForEach(displayElements, id: \.self) { element in
              elementLink(element, model: model)
            }
            .if(test(.delete)) {
              $0.onDelete(perform: deleteRow)
            }
          }
        }
      }
    }
    .animation(.spring(duration: 0.1), value: displayElements)
    .animation(.spring, value: permissions)
    .animation(.default, value: editMode?.wrappedValue)
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))

    .navigationBarTitleDisplayMode(.large)

    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
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
            .accessibilityLabel(String(localized: .app(.add)))
        }
        .disabled(!test(.add))

      }

      if #available(iOS 26.0, *) {
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
      }

      ToolbarItem(placement: .topBarTrailing) {
        CustomEditButton()
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
        hierarchy = model!.hierarchy()
      }
    }
  }
}

private struct Container<M: ManagerProtocol>: View {
  @StateObject public var store = DocumentStore(repository: PreviewRepository())
  @StateObject public var errorController = ErrorController()

  public var body: some View {
    NavigationStack {
      ManageView<M>()
        .navigationTitle("Title")
    }
    .environmentObject(store)
    .task {
      try? await store.fetchAll()
    }
  }
}

#Preview("TagManageView") {
  Container<TagManager>()
}

#Preview("CorrespondentManageView") {
  Container<CorrespondentManager>()
}
