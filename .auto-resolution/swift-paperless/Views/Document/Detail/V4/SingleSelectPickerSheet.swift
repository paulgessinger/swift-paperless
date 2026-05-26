//
//  SingleSelectPickerSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.04.26.
//

import AppShared
import DataModel
import Networking
import SwiftUI

private let singleSelectPickerDisplayLimit = 200

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
  let quickCreate: ((String) async throws -> Item)?
  @ViewBuilder let createView: (@escaping (Item) -> Void) -> CreateView

  @State private var searchText = ""
  @State private var searchIsActive: Bool
  @State private var selectedDetent: PresentationDetent
  @State private var saving = false
  @State private var showCreate = false
  @State private var sortedItems: [Item] = []

  init(
    viewModel: DocumentDetailModel,
    storeKeyPath: KeyPath<DocumentStore, [UInt: Item]>,
    keyPath: WritableKeyPath<Document, UInt?>,
    navigationTitle: LocalizedStringResource,
    listSectionTitle: LocalizedStringResource,
    notAssignedLabel: LocalizedStringResource,
    canCreate: Bool,
    suggestions: [UInt],
    quickCreate: ((String) async throws -> Item)? = nil,
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
    self.quickCreate = quickCreate
    self.createView = createView
    let nothingSelected = viewModel.document[keyPath: keyPath] == nil
    let autoFocus = nothingSelected && AppFeatures.enabled(.autoFocusSearchInDetailSheets)
    _searchIsActive = State(initialValue: autoFocus)
    _selectedDetent = State(initialValue: autoFocus ? .large : .medium)
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

  private func sortedByName(_ values: some Collection<Item>) -> [Item] {
    values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func computeMatching() -> (items: [Item], total: Int) {
    let selectedId = viewModel.document[keyPath: keyPath]
    let search = searchText
    var matched: [Item] = []
    matched.reserveCapacity(sortedItems.count)
    for item in sortedItems {
      if item.id == selectedId { continue }
      if !search.isEmpty, !item.name.localizedCaseInsensitiveContains(search) { continue }
      matched.append(item)
    }
    let limited = Array(matched.prefix(singleSelectPickerDisplayLimit))
    return (limited, matched.count)
  }

  @ViewBuilder
  private func itemLabel(_ item: Item, selected: Bool) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(item.name)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        Haptics.shared.notification(.success)
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

  private var trimmedSearch: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canQuickAdd: Bool {
    guard quickCreate != nil, canCreate else { return false }
    let search = trimmedSearch
    guard !search.isEmpty else { return false }
    return !allItems.values.contains {
      $0.name.localizedCaseInsensitiveCompare(search) == .orderedSame
    }
  }

  private func quickAdd() {
    guard !saving, let quickCreate else { return }
    let name = trimmedSearch
    guard !name.isEmpty else { return }
    let previous = viewModel.document[keyPath: keyPath]
    Task {
      do {
        saving = true
        let item = try await quickCreate(name)
        Haptics.shared.impact(style: .light)
        viewModel.document[keyPath: keyPath] = item.id
        async let update: Void = viewModel.updateDocument()
        async let delay: () = Task.sleep(for: .seconds(0.5))
        try await update
        Haptics.shared.notification(.success)
        try await delay
        saving = false
        dismiss()
      } catch {
        viewModel.document[keyPath: keyPath] = previous
        saving = false
        errorController.push(error: error)
      }
    }
  }

  private var quickAddRow: some View {
    Button {
      quickAdd()
    } label: {
      CustomSectionRow {
        HStack(alignment: .firstTextBaseline) {
          Image(systemName: "plus.circle.fill")
            .foregroundStyle(.secondary)
          Text(.app(.quickAdd(trimmedSearch)))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .buttonStyle(.plain)
    .allowsHitTesting(!saving)
    .transition(.opacity)
  }

  private func row(_ item: Item) -> some View {
    Button {
      select(id: item.id)
    } label: {
      CustomSectionRow {
        itemLabel(item, selected: false)
      }
    }
    .buttonStyle(.plain)
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
    let matching = computeMatching()
    return NavigationStack {
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
                    HStack(alignment: .firstTextBaseline) {
                      Text(.permissions(.private))
                        .italic()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(.app(.selected))
          }

          let showQuickAdd = canQuickAdd
          if !matching.items.isEmpty || showQuickAdd {
            CustomSection {
              LazyVStack(spacing: 0) {
                ForEach(Array(matching.items.enumerated()), id: \.element.id) { index, item in
                  row(item)
                  if index < matching.items.count - 1 {
                    Divider()
                  }
                }
                if showQuickAdd {
                  if !matching.items.isEmpty {
                    Divider()
                  }
                  quickAddRow
                }
              }
            } header: {
              Text(listSectionTitle)
            }
          }
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
            Label(String(localized: .app(.add)), systemImage: "plus")
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
      if sortedItems.isEmpty {
        sortedItems = sortedByName(allItems.values)
      }
    }
    .onChange(of: allItems.count) { _, _ in
      sortedItems = sortedByName(allItems.values)
    }
  }
}
