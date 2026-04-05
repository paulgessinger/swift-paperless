//
//  SingleSelectPickerSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.04.26.
//

import DataModel
import Networking
import SwiftUI

struct SingleSelectPickerSheet<Item: Model & Named & Hashable & Sendable, CreateView: View>: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  let allItems: () -> [Item]
  let keyPath: WritableKeyPath<Document, UInt?>
  let navigationTitle: LocalizedStringResource
  let listSectionTitle: LocalizedStringResource
  let notAssignedLabel: LocalizedStringResource
  let canCreate: Bool
  @ViewBuilder let createView: (@escaping (Item) -> Void) -> CreateView

  @State private var searchText = ""
  @State private var saving = false
  @State private var showCreate = false

  private let animation = Animation.spring(duration: 0.2)
  private static var selectedRowTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .bottom).combined(with: .opacity),
      removal: .move(edge: .bottom).combined(with: .opacity)
    )
  }

  private var selectedItem: Item? {
    viewModel.document[keyPath: keyPath].flatMap { id in
      allItems().first { $0.id == id }
    }
  }

  private var items: [Item] {
    let selectedId = viewModel.document[keyPath: keyPath]
    return allItems().filter { $0.id != selectedId }
  }

  private var filteredItems: [Item] {
    let search = searchText.lowercased()
    return
      items
      .filter { search.isEmpty || $0.name.lowercased().contains(search) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  @ViewBuilder
  private func itemLabel(_ item: Item, selected: Bool) -> some View {
    HStack {
      Text(item.name)
        .foregroundStyle(.primary)
      Spacer()
      if selected {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func select(id: UInt?) {
    guard !saving else { return }
    guard viewModel.document[keyPath: keyPath] != id else {
      dismiss()
      return
    }

    let previous = viewModel.document[keyPath: keyPath]
    Haptics.shared.impact(style: .light)
    viewModel.document[keyPath: keyPath] = id

    Task {
      do {
        saving = true
        try await Task.sleep(for: .seconds(0.1))
        async let updatedDocument = store.updateDocument(viewModel.document)
        async let delay: () = Task.sleep(for: .seconds(0.5))

        let updated = try await updatedDocument
        try await delay
        viewModel.document = updated
        saving = false
        if id != nil {
          dismiss()
        }
      } catch {
        viewModel.document[keyPath: keyPath] = previous
        saving = false
        errorController.push(error: error)
      }
    }
  }

  private func row(_ item: Item) -> some View {
    Button {
      select(id: item.id)
    } label: {
      CustomSectionRow {
        itemLabel(item, selected: false)
      }
    }
    .buttonStyle(.borderless)
    .allowsHitTesting(!saving)
    .id(item.id)
    .transition(
      .asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
      )
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          CustomSection {
            VStack {
              if let selectedItem {
                Button {
                  select(id: nil)
                } label: {
                  CustomSectionRow {
                    itemLabel(selectedItem, selected: true)
                  }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!saving)
                .transition(Self.selectedRowTransition)
                .id(selectedItem.id)
              } else {
                CustomSectionRow {
                  Text(notAssignedLabel)
                    .foregroundStyle(.secondary)
                }
                .transition(Self.selectedRowTransition)
              }
            }
            .animation(animation, value: viewModel.document[keyPath: keyPath])
          } header: {
            Text(.localizable(.selected))
          }

          VStack(spacing: 0) {
            if !filteredItems.isEmpty {
              CustomSection {
                VStack(spacing: 0) {
                  ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < filteredItems.count - 1 {
                      Divider()
                    }
                  }
                }
                .animation(animation, value: viewModel.document[keyPath: keyPath])
              } header: {
                Text(listSectionTitle)
              }
            }
          }
          .animation(animation, value: filteredItems.isEmpty)
        }
      }
      .customSectionBackground(.thickMaterial)
      .scrollBounceBehavior(.basedOnSize)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showCreate = true
          } label: {
            Label(String(localized: .localizable(.add)), systemImage: "plus")
          }
          .disabled(!canCreate)
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button {
              dismiss()
            } label: {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    }
    .interactiveDismissDisabled(saving)
    .sheet(isPresented: $showCreate) {
      NavigationStack {
        createView { item in
          select(id: item.id)
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            CancelIconButton()
          }
        }
      }
    }
    .onAppear {
      Haptics.shared.prepare()
    }
  }
}
