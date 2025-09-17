//
//  FilterBar.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 10.04.23.
//

import Combine
import Common
import DataModel
import Foundation
import Networking
import SwiftUI
import os

// @TODO: Add UI for FilterState with remaining rules!

// MARK: FilterMenu

extension ProtoSavedView: @retroactive Identifiable {
  public var id: UInt { 0 }
}

private struct SavedViewError: LocalizedError {
  var errorDescription: String? {
    "Active SavedView was not found in store and could not be saved"
  }
}

private struct FilterMenu<Content: View>: View {
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var filterModel: FilterModel
  @EnvironmentObject private var errorController: ErrorController
  @Binding var filterState: FilterState
  @Binding var savedView: ProtoSavedView?
  @ViewBuilder var label: () -> Content

  private func saveSavedView() {
    Logger.shared.info("Saving active saved view\("")")
    guard let id = filterModel.filterState.savedView, var updated = store.savedViews[id] else {
      errorController.push(message: "Unable to save active saved view")
      return
    }

    updated.filterRules = filterModel.filterState.rules
    updated.sortOrder = filterModel.filterState.sortOrder
    updated.sortField = filterModel.filterState.sortField
    Task {
      do {
        try await store.update(savedView: updated)
        filterModel.filterState = .init(savedView: updated)
      } catch {
        Logger.shared.error("Error saving saved view: \(error)")
        errorController.push(error: error)
      }
    }
    Logger.shared.info("Finished saving active saved view \(String(describing: updated))")
  }

  private var menuSavedViewSectionTitle: String {
    if let savedViewId = filterModel.filterState.savedView,
      let savedView = store.savedViews[savedViewId]
    {
      let indicator: String =
        if filterModel.filterState.modified {
          String(localized: .localizable(.savedViewModified(savedView.name)))
        } else {
          savedView.name
        }
      return "\(String(localized: .localizable(.savedView))): \(indicator)"
    }
    return String(localized: .localizable(.savedViews))
  }

  var body: some View {
    VStack {
      Menu {
        if filterModel.filterState.filtering, filterModel.filterState.modified {
          Section(menuSavedViewSectionTitle) {
            if let savedViewId = filterModel.filterState.savedView,
              let savedView = store.savedViews[savedViewId]
            {
              if store.permissions.test(.change, for: .savedView) {
                Button {
                  saveSavedView()
                } label: {
                  Label(
                    String(localized: .localizable(.save)), systemImage: "square.and.arrow.down")
                }
              }

              Button {
                filterModel.filterState = .init(savedView: savedView)
              } label: {
                Label(
                  String(localized: .localizable(.discardChanges)),
                  systemImage: "arrow.counterclockwise")
              }
            }

            if store.permissions.test(.add, for: .savedView) {
              Button {
                let proto = ProtoSavedView(
                  name: "",
                  sortField: filterModel.filterState.sortField,
                  sortOrder: filterModel.filterState.sortOrder,
                  filterRules: filterModel.filterState.rules
                )

                savedView = proto

              } label: {
                Label(String(localized: .localizable(.add)), systemImage: "plus.circle")
              }
            }
          }
        }

        if store.permissions.test(.view, for: .savedView) {
          NavigationLink {
            ManageView<SavedViewManager>()
              .navigationTitle(Text(.localizable(.savedViews)))
          } label: {
            Label(
              String(localized: .localizable(.savedViewsEditButtonLabel)),
              systemImage: "list.bullet")
          }
        }

        if filterState.filtering {
          if !store.savedViews.isEmpty, store.permissions.test(.view, for: .savedView) {
            Divider()
          }
          Text(.localizable(.filtersApplied(UInt(filterState.ruleCount))))
          Divider()
          Button(role: .destructive) {
            Haptics.shared.notification(.success)
            withAnimation {
              filterModel.filterState.clear()
              filterState.clear()
            }
          } label: {
            Label(String(localized: .localizable(.clearFilters)), systemImage: "xmark")
          }
        }

      } label: {
        label()
      }
    }
  }
}

private struct CircleCounter: View {
  enum Mode {
    case include
    case exclude
  }

  var value: Int
  var mode = Mode.include

  private var color: Color {
    switch mode {
    case .include:
      Color.accentColor
    case .exclude:
      Color.red
    }
  }

  var body: some View {
    Text(String("\(value)"))
      .foregroundColor(.white)
      .if(value == 1) { view in view.padding(5).padding(.leading, -1) }
      .if(value > 1) { view in view.padding(5) }
      .frame(minWidth: 20, minHeight: 20)
      .background(Circle().fill(color))
  }
}

// MARK: Common Element View

private struct CommonElementLabel<Element: Pickable>: View {
  @EnvironmentObject var store: DocumentStore

  let state: FilterState.Filter

  init(_: Element.Type, state: FilterState.Filter) {
    self.state = state
  }

  var body: some View {
    switch state {
    case .any:
      Text(Element.singularLabel)
    case .notAssigned:
      Text(Element.notAssignedFilter)
    case .anyOf(let ids):
      if ids.count == 1 {
        if let name = store[keyPath: Element.storePath][ids[0]]?.name {
          Text(name)
        } else {
          Text(Element.singularLabel)
            .redacted(reason: .placeholder)
        }
      } else {
        CircleCounter(value: ids.count, mode: .include)
        Text(Element.pluralLabel)
      }
    case .noneOf(let ids):
      if ids.count == 1 {
        Label(Element.excludeLabel, systemImage: "xmark")
          .labelStyle(.iconOnly)
        if let name = store[keyPath: Element.storePath][ids[0]]?.name {
          Text(name)
        } else {
          Text(Element.singularLabel)
            .redacted(reason: .placeholder)
        }
      } else {
        CircleCounter(value: ids.count, mode: .exclude)
        Text(Element.pluralLabel)
      }
    }
  }
}

// MARK: Element View

private struct Element<Label: View>: View {
  @ViewBuilder var label: () -> Label
  var active: Bool
  var action: () -> Void
  var chevron = true

  @State private var pressed = false

  var body: some View {
    Pill(active: active, chevron: chevron, label: label)
      .onTapGesture {
        Haptics.shared.impact(style: .light)
        action()
        Task {
          pressed = true
          try? await Task.sleep(for: .seconds(0.3))
          withAnimation {
            pressed = false
          }
        }
      }
      .opacity(pressed ? 0.7 : 1.0)
  }
}

private struct Pill<Label: View>: View {
  var active: Bool
  var chevron = true
  @ViewBuilder var label: () -> Label

  var body: some View {
    HStack {
      label()
        .fixedSize()
      if chevron {
        Image(systemName: "chevron.down")
      }
    }
    .frame(minHeight: 25)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background {
      Capsule()
        .fill(.background.tertiary)
    }
    .overlay {
      if active {
        Capsule()
          .strokeBorder(Color(.accent), lineWidth: 0.66)
      } else {
        Capsule()
          .strokeBorder(.tertiary, lineWidth: 0.66)
      }
    }
    .foregroundColor(active ? Color(.accent) : Color.primary)
    .if(active) { view in view.bold() }
  }
}

private struct SortMenu: View {
  @Binding var filterState: FilterState
  @EnvironmentObject private var store: DocumentStore

  private var eligibleSortFields: [SortField] {
    let isAdvancedSearch = !filterState.searchText.isEmpty && filterState.searchMode == .advanced

    let inclusive =
      SortField.allCases
      + store.customFields
      .map(\.value)
      .sorted { $0.name < $1.name }
      .map { SortField.customField($0.id) }

    if isAdvancedSearch || filterState.sortField == .score {
      return inclusive
    } else {
      return inclusive.filter { $0 != .score }
    }
  }

  var body: some View {
    Menu {
      Picker(String(localized: .localizable(.sortOrder)), selection: $filterState.sortOrder) {
        Label(SortOrder.ascending.localizedName, systemImage: "arrow.up")
          .tag(SortOrder.ascending)
        Label(SortOrder.descending.localizedName, systemImage: "arrow.down")
          .tag(SortOrder.descending)
      }

      Picker(String(localized: .localizable(.sortBy)), selection: $filterState.sortField) {
        ForEach(eligibleSortFields, id: \.rawValue) { f in
          Text(f.localizedName(customFields: store.customFields)).tag(f)
        }
        if case .other(let value) = filterState.sortField {
          Text(value)
            .tag(SortField.other(value))
        }
      }
    } label: {
      Element(
        label: {
          Label(String(localized: .localizable(.sortMenuLabel)), systemImage: "arrow.up.arrow.down")
            .labelStyle(.iconOnly)
        }, active: !filterState.defaultSorting, action: {})
    }
    .onTapGesture {
      Haptics.shared.impact(style: .light)
    }
  }
}

struct FilterBar: View {
  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var filterModel: FilterModel
  @Environment(\.dismiss) private var dismiss

  @State private var showTags = false
  @State private var showDocumentType = false
  @State private var showCorrespondent = false
  @State private var showStoragePath = false
  @State private var showCustomFields = false

  private enum ModalMode {
    case tags
    case correspondent
    case documentType
    case storagePath
    case customFields
  }

  @State private var filterState = FilterState.default

  @State var offset = CGSize()
  @State var menuWidth = 0.0
  @State var filterMenuHit = false

  @State private var savedView: ProtoSavedView? = nil

  private struct Modal<Content: View>: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var filterModel: FilterModel
    @Environment(\.dismiss) private var dismiss

    var title: String
    @Binding var filterState: FilterState
    var onDismiss: () -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
      NavigationStack {
        VStack {
          content()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            Button {
              dismiss()
              filterModel.filterState = filterState
              onDismiss()
            } label: {
              Text(.localizable(.done))
                .accessibilityIdentifier("dismissButton")
            }
          }
        }
      }
    }
  }

  // MARK: present()

  private func present(_ mode: ModalMode) {
    //        impact.impactOccurred()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
      switch mode {
      case .tags:
        showTags = true
      case .correspondent:
        showCorrespondent = true
      case .documentType:
        showDocumentType = true
      case .storagePath:
        showStoragePath = true
      case .customFields:
        showCustomFields = true
      }
    }
  }

  private struct AddSavedViewSheet: View {
    var savedView: ProtoSavedView

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var filterModel: FilterModel

    var body: some View {
      NavigationStack {
        SavedViewEditView(element: savedView) { savedView in
          Task {
            do {
              let created = try await store.create(savedView: savedView)
              filterModel.filterState = .init(savedView: created)
              dismiss()
            } catch {
              print(error)
            }
          }
        }
        .toolbar {
          ToolbarItem(placement: .navigationBarLeading) {
            Button(String(localized: .localizable(.cancel))) {
              dismiss()
            }
          }
        }
      }
    }
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        Pill(active: filterState.filtering || filterState.savedView != nil, chevron: false) {
          Label(
            String(localized: .localizable(.filtering)), systemImage: "line.3.horizontal.decrease"
          )
          .labelStyle(.iconOnly)
          if filterModel.filterState.filtering {
            CircleCounter(value: filterModel.filterState.ruleCount)
          }
        }
        .opacity(filterMenuHit ? 0.5 : 1.0)
        .overlay {
          GeometryReader { geo in
            FilterMenu(filterState: $filterState, savedView: $savedView) {
              Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
            }
          }
          .onTapGesture {
            Task {
              Haptics.shared.prepare()
              Haptics.shared.impact(style: .light)
              filterMenuHit = true
              try? await Task.sleep(for: .seconds(0.3))
              withAnimation { filterMenuHit = false }
            }
          }
        }

        .onChange(of: offset) {
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
              menuWidth = offset.width
            }
          }
        }

        Element(
          label: {
            switch filterState.tags {
            case .any:
              Text(.localizable(.tags))
            case .notAssigned:
              Text(.localizable(.tagsNotAssignedFilter))
            case .allOf(let include, let exclude):
              let count = include.count + exclude.count
              if count == 1 {
                if let i = include.first, let name = store.tags[i]?.name {
                  Text(name)
                } else if let i = exclude.first, let name = store.tags[i]?.name {
                  Label(String(localized: .localizable(.tagExclude)), systemImage: "xmark")
                    .labelStyle(.iconOnly)
                  Text(name)
                } else {
                  Text(.localizable(.numberOfTags(1)))
                    .redacted(reason: .placeholder)
                }
              } else {
                if !include.isEmpty, !exclude.isEmpty {
                  CircleCounter(value: include.count, mode: .include)
                  Text(String("/"))
                  CircleCounter(value: exclude.count, mode: .exclude)
                } else if !include.isEmpty {
                  CircleCounter(value: count, mode: .include)
                } else {
                  CircleCounter(value: count, mode: .exclude)
                }
                Text(.localizable(.tags))
              }
            case .anyOf(let ids):
              if ids.count == 1 {
                if let name = store.tags[ids.first!]?.name {
                  Text(name)
                } else {
                  Text(.localizable(.numberOfTags(1)))
                    .redacted(reason: .placeholder)
                }
              } else {
                CircleCounter(value: ids.count)
                Text(.localizable(.tags))
              }
            }
          }, active: filterState.tags != .any
        ) {
          present(.tags)
        }
        .accessibilityIdentifier("filterBarTagsFilterButton")

        Element(
          label: {
            CommonElementLabel(
              DocumentType.self,
              state: filterState.documentType)
          }, active: filterState.documentType != .any
        ) { present(.documentType) }

        Element(
          label: {
            CommonElementLabel(
              Correspondent.self,
              state: filterState.correspondent)
          }, active: filterState.correspondent != .any
        ) { present(.correspondent) }

        Element(
          label: {
            CommonElementLabel(
              StoragePath.self,
              state: filterState.storagePath)
          }, active: filterState.storagePath != .any
        ) { present(.storagePath) }

        Pill(active: filterState.owner != .any) {
          switch filterState.owner {
          case .any:
            Text(.localizable(.permissions))
          case .anyOf(let ids):
            if ids.count == 1, ids[0] == store.currentUser?.id {
              Text(.localizable(.ownerMyDocuments))
            } else {
              CircleCounter(value: ids.count, mode: .include)
              Text(.localizable(.ownerMultipleUsers))
            }
          case .noneOf(let ids):
            if ids.count == 1, ids[0] == store.currentUser?.id {
              Text(.localizable(.ownerSharedWithMe))
            } else {
              CircleCounter(value: ids.count, mode: .exclude)
              Text(.localizable(.ownerMultipleUsers))
            }
          case .notAssigned:
            Text(.localizable(.ownerUnowned))
          }
        }
        .overlay {
          GeometryReader { geo in

            Menu {
              Button {
                withAnimation {
                  filterModel.filterState.owner = .any
                }
              } label: {
                let text = String(localized: .localizable(.ownerAll))
                if filterState.owner == .any {
                  Label(text, systemImage: "checkmark")
                } else {
                  Text(text)
                }
              }

              if let user = store.currentUser {
                Button {
                  withAnimation {
                    filterModel.filterState.owner = .anyOf(ids: [user.id])
                  }
                } label: {
                  let text = String(localized: .localizable(.ownerMyDocuments))
                  switch filterState.owner {
                  case .anyOf(let ids):
                    if ids.count == 1, ids[0] == store.currentUser?.id {
                      Label(text, systemImage: "checkmark")
                    } else {
                      Text(text)
                    }
                  default:
                    Text(text)
                  }
                }
                Button {
                  withAnimation {
                    filterModel.filterState.owner = .noneOf(ids: [user.id])
                  }
                } label: {
                  let text = String(localized: .localizable(.ownerSharedWithMe))
                  switch filterState.owner {
                  case .noneOf(let ids):
                    if ids.count == 1, ids[0] == store.currentUser?.id {
                      Label(text, systemImage: "checkmark")
                    } else {
                      Text(text)
                    }
                  default:
                    Text(text)
                  }
                }
              }
              Button {
                withAnimation {
                  filterModel.filterState.owner = .notAssigned
                }

              } label: {
                let text = String(localized: .localizable(.ownerUnowned))
                if filterState.owner == .notAssigned {
                  Label(text, systemImage: "checkmark")
                } else {
                  Text(text)
                }
              }

              switch filterState.owner {
              case .anyOf(let ids), .noneOf(let ids):
                if ids.count > 1 || (ids.count == 1 && ids[0] != store.currentUser?.id) {
                  Divider()
                  Text(String(localized: .localizable(.ownerFilterExplicitUnsupported)))
                } else {
                  EmptyView()
                }
              case .notAssigned, .any:
                EmptyView()
              }
            } label: {
              Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onTapGesture {
              Haptics.shared.impact(style: .light)
            }
          }
        }

        Element(
          label: {
            Text(.customFields(.title))
          }, active: filterModel.filterState.customField != .any
        ) { present(.customFields) }

        Divider()

        SortMenu(filterState: $filterState)
      }
      .padding(.horizontal)
      .foregroundColor(.primary)
    }
    .scaledToFit()
    .padding(.vertical, 5)

    .task {
      try? await Task.sleep(for: .seconds(0.5))
      withAnimation {
        filterState = filterModel.filterState
      }
    }

    .onChange(of: filterState.sortOrder) { _, value in
      filterModel.filterState.sortOrder = value
    }

    .onChange(of: filterState.sortField) { _, value in
      filterModel.filterState.sortField = value
    }

    // MARK: Sheets

    .sheet(isPresented: $showTags) {
      Modal(title: String(localized: .localizable(.tags)), filterState: $filterState) {
        TagFilterView(
          selectedTags: $filterState.tags)
      }
    }

    .sheet(isPresented: $showDocumentType) {
      Modal(title: String(localized: .localizable(.documentType)), filterState: $filterState) {
        CommonPickerFilterView(
          selection: $filterState.documentType,
          elements: store.documentTypes.sorted {
            $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending
          }.map { ($0.value.id, $0.value.name) },
          notAssignedLabel: String(localized: .localizable(.documentTypeNotAssignedPicker))
        )
      }
    }

    .sheet(isPresented: $showCorrespondent) {
      Modal(title: String(localized: .localizable(.correspondent)), filterState: $filterState) {
        CommonPickerFilterView(
          selection: $filterState.correspondent,
          elements: store.correspondents.sorted {
            $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending
          }.map { ($0.value.id, $0.value.name) },
          notAssignedLabel: String(localized: .localizable(.correspondentNotAssignedPicker))
        )
      }
    }

    .sheet(isPresented: $showStoragePath) {
      Modal(title: String(localized: .localizable(.storagePath)), filterState: $filterState) {
        CommonPickerFilterView(
          selection: $filterState.storagePath,
          elements: store.storagePaths.sorted {
            $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending
          }.map { ($0.value.id, $0.value.name) },
          notAssignedLabel: String(localized: .localizable(.storagePathNotAssignedPicker))
        )
      }
    }

    .sheet(isPresented: $showCustomFields) {
      CustomFieldFilterView(query: $filterModel.filterState.customField)
    }

    .sheet(item: $savedView) { view in
      AddSavedViewSheet(savedView: view)
    }

    // @TODO: Revisit if this is needed still, if not simplify
    .onReceive(filterModel.filterStatePublisher) { value in
      DispatchQueue.main.async {
        withAnimation {
          filterState = value
        }
      }
    }
  }
}

private let customFields = [
  CustomField(id: 1, name: "Custom float", dataType: .float),
  CustomField(id: 2, name: "Custom bool", dataType: .boolean),
  CustomField(id: 4, name: "Custom integer", dataType: .integer),
]

#Preview {
  @Previewable @StateObject var store = DocumentStore(repository: TransientRepository())
  @Previewable @StateObject var filterModel = FilterModel()
  @Previewable @StateObject var errorController = ErrorController()

  NavigationStack {
    Form {
      FilterBar()
        .environmentObject(store)
        .environmentObject(filterModel)
        .environmentObject(errorController)

      Section {
        Text(String(describing: filterModel.filterState))
      }
    }
  }
  .task {
    do {
      let repository = store.repository as! TransientRepository
      await repository.addUser(
        User(id: 1, isSuperUser: false, username: "user", groups: [1]))
      try? await repository.login(userId: 1)
      for field in customFields {
        _ = try await repository.add(customField: field)
      }

      _ = try await store.create(tag: ProtoTag(name: "Inbox"))
      _ = try await store.create(correspondent: ProtoCorrespondent(name: "Test Correspondent"))
      _ = try await store.create(documentType: ProtoDocumentType(name: "Test Document Type"))
      _ = try await store.create(storagePath: ProtoStoragePath(name: "Test Storage Path"))

      try await store.fetchAll()
      try await store.repository.create(
        document: ProtoDocument(title: "blubb"),
        file: #URL("http://example.com"), filename: "blubb.pdf"
      )
    } catch {}
  }
}
