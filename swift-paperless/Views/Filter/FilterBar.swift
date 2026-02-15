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

private enum TransitionKeys: String {
  case tags, documentType, correspondent, storagePath, customFields, asn, date
}

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
            filterModel.filterState.clear()
            filterState.clear()
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

  private var bg: Color {
    switch mode {
    case .include:
      if #available(iOS 26.0, *) {
        Color.accentColorLightened
      } else {
        Color.accentColor
      }

    case .exclude:
      Color.red
    }
  }

  private var fg: Color {
    .white
  }

  var body: some View {
    Text(String("\(value)"))
      .foregroundColor(fg)
      .if(value == 1) { view in view.padding(5).padding(.leading, -1) }
      .if(value > 1) { view in view.padding(5) }
      .frame(minWidth: 20, minHeight: 20)
      .background(Circle().fill(bg))
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

  private func onTap() {
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

  var body: some View {
    if #available(iOS 26.0, *) {
      Button {
        action()
      } label: {
        Pill(active: active, chevron: chevron, label: label)
      }
    } else {
      Pill(active: active, chevron: chevron, label: label)
        .onTapGesture {
          action()
        }
        .opacity(pressed ? 0.7 : 1.0)
    }
  }
}

private struct Pill<Label: View>: View {
  var active: Bool
  var chevron = true
  @ViewBuilder var label: () -> Label

  var body: some View {
    if #available(iOS 26.0, *) {
      PillLiquidGlass(active: active, chevron: chevron, label: label)
    } else {
      PilliOS18(active: active, chevron: chevron, label: label)
    }
  }
}

@available(iOS 26.0, *)
private struct PillLiquidGlass<Label: View>: View {
  var active: Bool
  var chevron = true
  @ViewBuilder var label: () -> Label

  private var activeColor: Color {
    .accentColorLightened
  }

  var body: some View {
    HStack {
      label()
        .fixedSize()
      if chevron {
        Image(systemName: "chevron.down")
      }
    }
    .frame(minWidth: 25, minHeight: 35)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .foregroundColor(active ? activeColor : Color.primary)
    .fontWeight(active ? .bold : .regular)
    .glassEffect(.regular.interactive())
  }
}

private struct PilliOS18<Label: View>: View {
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

    if isAdvancedSearch || filterState.sortField == .score {
      return inclusive
    } else {
      return inclusive.filter { $0 != .score }
    }
  }

  private var customFields: [SortField] {
    store.customFields
      .map(\.value)
      .sorted { $0.name < $1.name }
      .map { SortField.customField($0.id) }
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

      Picker(String(localized: .localizable(.customFields)), selection: $filterState.sortField) {
        ForEach(customFields, id: \.rawValue) { f in
          Text(f.localizedName(customFields: store.customFields)).tag(f)
        }
      }
      .pickerStyle(.menu)
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
  @Environment(RouteManager.self) private var routeManager

  @State private var showTags = false
  @State private var showDocumentType = false
  @State private var showCorrespondent = false
  @State private var showStoragePath = false
  @State private var showCustomFields = false
  @State private var showAsn = false
  @State private var showDate = false

  private enum ModalMode {
    case tags
    case correspondent
    case documentType
    case storagePath
    case customFields
    case asn
    case date
  }

  @State private var filterState = FilterState.default

  @State private var savedView: ProtoSavedView? = nil

  @Namespace private var transition

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
            SaveButton {
              dismiss()
              filterModel.filterState = filterState
              onDismiss()
            }
          }
        }
      }
    }
  }

  // MARK: present()

  private func present(_ mode: ModalMode) {
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
      case .asn:
        showAsn = true
      case .date:
        showDate = true
      }
    }
  }

  private func closeAll() {
    showTags = false
    showCorrespondent = false
    showDocumentType = false
    showStoragePath = false
    showCustomFields = false
    showAsn = false
    showDate = false
  }

  private func handlePendingRoute() {
    guard let action = routeManager.pendingRoute?.action else { return }
    switch action {
    case .openFilterSettings(let setting):
      closeAll()
      routeManager.pendingRoute = nil
      let target: ModalMode =
        switch setting {
        case .tags: .tags
        case .asn: .asn
        case .correspondent: .correspondent
        case .documentType: .documentType
        case .storagePath: .storagePath
        case .date: .date
        case .customField: .customFields
        }
      present(target)
    case .closeFilterSettings:
      closeAll()
      routeManager.pendingRoute = nil
    default:
      break
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

  private var tagElement: some View {

    Element(
      label: {
        Group {
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
        }

        .backport.matchedTransitionSource(
          id: TransitionKeys.tags, in: transition
        )
      }, active: filterState.tags != .any
    ) {
      present(.tags)
    }
    .accessibilityIdentifier("filterBarTagsFilterButton")
  }

  private func ownerMenu<B: View>(@ViewBuilder content: () -> B) -> some View {
    Menu {
      Button {
        filterModel.filterState.owner = .any
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
          filterModel.filterState.owner = .anyOf(ids: [user.id])
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
          filterModel.filterState.owner = .noneOf(ids: [user.id])
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
        filterModel.filterState.owner = .notAssigned
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
      content()
    }
  }

  private var ownerElement: some View {
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
  }

  private var configuredComponents: [FilterBarComponent] {
    switch AppSettings.shared.filterBarConfiguration {
    case .default:
      return FilterBarComponent.allCases
    case .configured(let components):
      return components
    }
  }

  @ViewBuilder
  private func componentView(_ component: FilterBarComponent) -> some View {
    switch component {
    case .tags:
      tagElement
    case .documentType:
      Element(
        label: {
          CommonElementLabel(
            DocumentType.self,
            state: filterState.documentType
          )
          .backport.matchedTransitionSource(
            id: TransitionKeys.documentType, in: transition
          )
        }, active: filterState.documentType != .any
      ) { present(.documentType) }
    case .correspondent:
      Element(
        label: {
          CommonElementLabel(
            Correspondent.self,
            state: filterState.correspondent
          )
          .backport.matchedTransitionSource(
            id: TransitionKeys.correspondent, in: transition
          )
        }, active: filterState.correspondent != .any
      ) { present(.correspondent) }
    case .storagePath:
      Element(
        label: {
          CommonElementLabel(
            StoragePath.self,
            state: filterState.storagePath
          )
          .backport.matchedTransitionSource(
            id: TransitionKeys.storagePath, in: transition
          )
        }, active: filterState.storagePath != .any
      ) { present(.storagePath) }
    case .permissions:
      ownerElement
        .overlay {
          GeometryReader { geo in
            ownerMenu {
              Color.clear
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onTapGesture {
              Haptics.shared.impact(style: .light)
            }
          }
        }
    case .customFields:
      Element(
        label: {
          Text(.customFields(.title))
            .backport.matchedTransitionSource(
              id: TransitionKeys.customFields, in: transition
            )
        }, active: filterModel.filterState.customField != .any
      ) { present(.customFields) }
    case .asn:
      Element(
        label: {
          AsnFilterDisplayView(query: filterModel.filterState.asn)
            .backport.matchedTransitionSource(
              id: TransitionKeys.asn, in: transition
            )
        }, active: filterModel.filterState.asn != .any
      ) { present(.asn) }
    case .date:
      Element(
        label: {
          DateFilterDisplayView(query: filterModel.filterState.date)
            .backport.matchedTransitionSource(
              id: TransitionKeys.date, in: transition
            )
        }, active: filterModel.filterState.date.isActive
      ) { present(.date) }
    }
  }

  private var barContent: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        FilterMenu(filterState: $filterState, savedView: $savedView) {
          Pill(active: filterState.filtering || filterState.savedView != nil, chevron: false) {
            Label(
              String(localized: .localizable(.filtering)), systemImage: "line.3.horizontal.decrease"
            )
            .labelStyle(.iconOnly)
            if filterModel.filterState.filtering {
              CircleCounter(value: filterModel.filterState.ruleCount)
            }
          }
        }

        ForEach(configuredComponents, id: \.self) { component in
          componentView(component)
        }

        Divider()

        SortMenu(filterState: $filterState)
      }
      .padding(.horizontal)
    }
    .animation(.default, value: filterModel.filterState)
  }

  @ViewBuilder
  private var barView: some View {
    if #available(iOS 26.0, *) {
      GlassEffectContainer {
        barContent
      }
    } else {
      barContent
    }
  }

  var body: some View {
    barView
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

      .onChange(of: routeManager.pendingRoute, initial: true, handlePendingRoute)

      // MARK: Sheets

      .sheet(isPresented: $showTags) {
        Modal(title: String(localized: .localizable(.tags)), filterState: $filterState) {
          TagFilterView(
            selectedTags: $filterState.tags)
        }
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.tags, in: transition)
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
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.documentType, in: transition)
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
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.correspondent, in: transition)
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
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.storagePath, in: transition)
      }

      .sheet(isPresented: $showCustomFields) {
        CustomFieldFilterView(query: $filterModel.filterState.customField)
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.customFields, in: transition)
      }

      .sheet(isPresented: $showAsn) {
        AsnFilterView(query: $filterModel.filterState.asn)
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.asn, in: transition)
      }

      .sheet(isPresented: $showDate) {
        DateFilterView(query: $filterModel.filterState.date)
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.date, in: transition)
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
        .environment(RouteManager.shared)

      Section {
        Text(String(describing: filterModel.filterState))
      }
    }
  }
  .task {
    do {
      let repository = store.repository as! TransientRepository
      repository.addUser(
        User(id: 1, isSuperUser: false, username: "user", groups: [1]))
      try? repository.login(userId: 1)
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
