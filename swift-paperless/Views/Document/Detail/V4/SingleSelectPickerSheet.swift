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

  let storeKeyPath: KeyPath<DocumentStore, [UInt: Item]>
  let keyPath: WritableKeyPath<Document, UInt?>
  let navigationTitle: LocalizedStringResource
  let listSectionTitle: LocalizedStringResource
  let notAssignedLabel: LocalizedStringResource
  let canCreate: Bool
  let suggestions: [UInt]
  @ViewBuilder let createView: (@escaping (Item) -> Void) -> CreateView

  @State private var searchText = ""
  @State private var searchIsActive: Bool
  @State private var selectedDetent: PresentationDetent
  @State private var saving = false
  @State private var showCreate = false

  init(
    viewModel: DocumentDetailModel,
    storeKeyPath: KeyPath<DocumentStore, [UInt: Item]>,
    keyPath: WritableKeyPath<Document, UInt?>,
    navigationTitle: LocalizedStringResource,
    listSectionTitle: LocalizedStringResource,
    notAssignedLabel: LocalizedStringResource,
    canCreate: Bool,
    suggestions: [UInt],
    @ViewBuilder createView: @escaping (@escaping (Item) -> Void) -> CreateView
  ) {
    self.viewModel = viewModel
    self.storeKeyPath = storeKeyPath
    self.keyPath = keyPath
    self.navigationTitle = navigationTitle
    self.listSectionTitle = listSectionTitle
    self.notAssignedLabel = notAssignedLabel
    self.canCreate = canCreate
    self.suggestions = suggestions
    self.createView = createView
    let nothingSelected = viewModel.document[keyPath: keyPath] == nil
    _searchIsActive = State(initialValue: nothingSelected)
    _selectedDetent = State(initialValue: nothingSelected ? .large : .medium)
  }

  private let animation = Animation.spring(duration: 0.2)
  private static var selectedRowTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: .bottom).combined(with: .opacity),
      removal: .move(edge: .bottom).combined(with: .opacity)
    )
  }

  private enum Selection {
    case notAssigned
    case `private`
    case item(Item)
  }

  private var allItems: [UInt: Item] {
    store[keyPath: storeKeyPath]
  }

  private var selection: Selection {
    guard let id = viewModel.document[keyPath: keyPath] else {
      return .notAssigned
    }
    guard let item = allItems[id] else {
      return .private
    }
    return .item(item)
  }

  private var suggestedItems: [Item] {
    let selectedId = viewModel.document[keyPath: keyPath]
    return
      suggestions
      .filter { $0 != selectedId }
      .compactMap { allItems[$0] }
  }

  private var filteredItems: [Item] {
    let selectedId = viewModel.document[keyPath: keyPath]
    let search = searchText.lowercased()
    return allItems.values
      .filter { $0.id != selectedId }
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
        async let update: Void = viewModel.updateDocument()
        async let delay: () = Task.sleep(for: .seconds(0.5))

        try await update
        try await delay
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
            VStack(alignment: .leading, spacing: 0) {
              switch selection {
              case .item(let selectedItem):
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
              case .private:
                Button {
                  select(id: nil)
                } label: {
                  CustomSectionRow {
                    HStack {
                      Text(.permissions(.private))
                        .italic()
                        .foregroundStyle(.secondary)
                      Spacer()
                      Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!saving)
                .transition(Self.selectedRowTransition)
              case .notAssigned:
                CustomSectionRow {
                  Text(notAssignedLabel)
                    .foregroundStyle(.secondary)
                }
                .transition(Self.selectedRowTransition)
              }

              if !suggestedItems.isEmpty {
                SuggestionsRow {
                  ForEach(suggestedItems, id: \.id) { item in
                    SuggestionPill(text: item.name) {
                      select(id: item.id)
                    }
                  }
                }
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
      .searchable(
        text: $searchText, isPresented: $searchIsActive,
        placement: .navigationBarDrawer(displayMode: .always)
      )
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
    .presentationDetents([.medium, .large], selection: $selectedDetent)
    .onAppear {
      Haptics.shared.prepare()
    }
  }
}
