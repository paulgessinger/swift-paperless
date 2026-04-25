//
//  TagSelectionView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.03.23.
//

import DataModel
import Networking
import SwiftUI

// - MARK: TagFilterView

// - MARK: TagEditView
struct DocumentTagEditView<D>: View where D: DocumentProtocol {
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Binding var document: D

  @State private var searchText = ""

  @Namespace private var animation

  private struct CreateTag: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.dismiss) private var dismiss

    @Binding var document: D

    var body: some View {
      TagEditView<ProtoTag>(onSave: { value in
        Task {
          do {
            let tag = try await store.create(tag: value)
            document.tags.append(tag.id)
            dismiss()
          } catch {
            errorController.push(error: error)
            throw error
          }
        }
      })
    }
  }

  private func row(
    action: @escaping () -> Void,
    active: Bool,
    @ViewBuilder content: () -> some View
  ) -> some View {
    HStack {
      Button(action: { withAnimation { action() } }, label: content)
        .foregroundColor(.primary)
      Spacer()
      if active {
        Label(String(localized: .localizable(.tagIsSelected)), systemImage: "checkmark")
          .labelStyle(.iconOnly)
      }
    }
  }

  private func tagFilter(tag: Tag) -> Bool {
    if document.tags.contains(tag.id) { return false }
    if searchText.isEmpty { return true }
    if tag.name.range(of: searchText, options: .caseInsensitive) != nil {
      return true
    } else {
      return false
    }
  }

  private var displayTags: [Tag] {
    store.tags.values
      .filter { tagFilter(tag: $0) }
      .sorted { $0.name < $1.name }
  }

  /// Hierarchical version of `displayTags` returning each tag paired with its
  /// nesting depth (0 = root). Children appear immediately under their parent;
  /// a child whose parent is filtered out (or absent) is treated as a root so
  /// it stays visible. Returns `nil` while searching, so callers fall back to
  /// the flat list — depth-first ordering hurts cross-tree search results.
  private var displayTagsHierarchical: [(tag: Tag, depth: Int)]? {
    guard searchText.isEmpty else { return nil }
    let visible = displayTags
    guard visible.contains(where: { $0.parent != nil }) else { return nil }

    let visibleIds = Set(visible.map(\.id))
    var byParent: [UInt?: [Tag]] = [:]
    for tag in visible {
      let key: UInt? = tag.parent.flatMap { visibleIds.contains($0) ? $0 : nil }
      byParent[key, default: []].append(tag)
    }

    var result: [(tag: Tag, depth: Int)] = []
    func walk(_ parent: UInt?, depth: Int) {
      for tag in byParent[parent] ?? [] {
        result.append((tag, depth))
        walk(tag.id, depth: depth + 1)
      }
    }
    walk(nil, depth: 0)
    return result
  }

  @ViewBuilder
  private func availableRow(tag: Tag, depth: Int) -> some View {
    Button(action: {
      withAnimation {
        document.tags.append(tag.id)
      }
    }) {
      HStack {
        TagView(tag: tag)
        Spacer()
        Label(String(localized: .localizable(.tagAdd)), systemImage: "plus.circle")
          .labelStyle(.iconOnly)
          .foregroundColor(.accentColor)
      }
      .padding(.leading, CGFloat(depth) * 16)
    }
  }

  private struct NoElementsView: View {
    var body: some View {
      ContentUnavailableView(
        String(localized: .localizable(.noElementsFound)),
        systemImage: "exclamationmark.magnifyingglass",
        description: Text(Tag.localizedNamePlural))
    }
  }

  private struct NoPermissionsView: View {
    var body: some View {
      ContentUnavailableView(
        String(localized: .permissions(.noViewPermissionsDisplayTitle)),
        systemImage: "lock.fill",
        description: Text(Tag.localizedNoViewPermissions))
    }
  }

  var body: some View {
    Form {
      if !store.permissions.test(.view, for: .tag) {
        NoPermissionsView()
      } else {
        Section {
          ForEach(document.tags, id: \.self) { id in
            let tag = store.tags[id]
            Button(action: {
              withAnimation {
                document.tags = document.tags.filter { $0 != id }
              }
            }) {
              HStack {
                TagView(tag: tag)
                Spacer()
                Label(String(localized: .localizable(.remove)), systemImage: "xmark.circle.fill")
                  .labelStyle(.iconOnly)
                  .foregroundColor(.gray)
              }
            }
          }
          if document.tags.isEmpty {
            Text(.localizable(.none))
          }
        } header: {
          Text(.localizable(.selected))
        }

        Section {
          if let hierarchical = displayTagsHierarchical {
            ForEach(hierarchical, id: \.tag.id) { entry in
              availableRow(tag: entry.tag, depth: entry.depth)
            }
          } else {
            ForEach(displayTags, id: \.id) { tag in
              availableRow(tag: tag, depth: 0)
            }
          }
        }
      }
    }
    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))

    .animation(.spring, value: displayTags)
    .animation(.spring, value: store.permissions[.tag])

    .refreshable {
      Task {
        do {
          try await store.fetchAll()
        } catch {
          errorController.push(error: error)
        }
      }
    }

    .navigationTitle(Text(.localizable(.tags)))

    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        NavigationLink {
          CreateTag(document: $document)
        } label: {
          Label(String(localized: .localizable(.tagAdd)), systemImage: "plus")
        }

        .disabled(!store.permissions.test(.add, for: .tag))
      }
    }
  }
}
