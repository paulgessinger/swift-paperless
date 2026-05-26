//
//  FilterBar.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 10.04.23.
//

import AppShared
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
  @Environment(FilterModel.self) private var filterModel
  @EnvironmentObject private var errorController: ErrorController
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
          String(localized: .app(.savedViewModified(savedView.name)))
        } else {
          savedView.name
        }
      return "\(String(localized: .app(.savedView))): \(indicator)"
    }
    return String(localized: .app(.savedViews))
  }

  var body: some View {
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
                  String(localized: .app(.save)), systemImage: "square.and.arrow.down")
              }
            }

            Button {
              filterModel.filterState = .init(savedView: savedView)
            } label: {
              Label(
                String(localized: .app(.discardChanges)),
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
              Label(String(localized: .app(.add)), systemImage: "plus.circle")
            }
          }
        }
      }

      if store.permissions.test(.view, for: .savedView) {
        NavigationLink {
          ManageView<SavedViewManager>()
            .navigationTitle(Text(.app(.savedViews)))
        } label: {
          Label(
            String(localized: .app(.savedViewsEditButtonLabel)),
            systemImage: "list.bullet")
        }
      }

      if filterModel.filterState.filtering {
        if !store.savedViews.isEmpty, store.permissions.test(.view, for: .savedView) {
          Divider()
        }
        Text(.app(.filtersApplied(filterModel.filterState.defaultAwareRuleCount)))
        Divider()
        Button(role: .destructive) {
          Haptics.shared.notification(.success)
          filterModel.filterState.clear()
        } label: {
          Label(String(localized: .app(.clearFilters)), systemImage: "xmark")
        }
      }

    } label: {
      label()
    }
    .backport.glassEffect(.regular.interactive())
  }
}

private struct CircleCounter<Value: CustomStringConvertible>: View {
  enum Mode {
    case include
    case exclude
  }

  var value: Value
  var mode = Mode.include

  private var text: String {
    String(describing: value)
  }

  private var contentPadding: EdgeInsets {
    EdgeInsets(top: 5, leading: text == "1" ? 4 : 5, bottom: 5, trailing: 5)
  }

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
    Text(text)
      .foregroundColor(fg)
      .padding(contentPadding)
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
      .glassEffect(.regular.interactive())
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
  @Environment(FilterModel.self) private var filterModel
  @EnvironmentObject private var store: DocumentStore

  private var eligibleSortFields: [SortField] {
    let isAdvancedSearch =
      !filterModel.filterState.searchText.isEmpty && filterModel.filterState.searchMode == .advanced

    let inclusive =
      SortField.allCases

    if isAdvancedSearch || filterModel.filterState.sortField == .score {
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
    @Bindable var filterModel = filterModel

    Menu {
      Picker(
        String(localized: .app(.sortOrder)),
        selection: $filterModel.filterState.sortOrder
      ) {
        Label(SortOrder.ascending.localizedName, systemImage: "arrow.up")
          .tag(SortOrder.ascending)
        Label(SortOrder.descending.localizedName, systemImage: "arrow.down")
          .tag(SortOrder.descending)
      }

      Picker(
        String(localized: .app(.sortBy)),
        selection: $filterModel.filterState.sortField
      ) {
        ForEach(eligibleSortFields, id: \.rawValue) { f in
          Text(f.localizedName(customFields: store.customFields)).tag(f)
        }
        if case .other(let value) = filterModel.filterState.sortField {
          Text(value)
            .tag(SortField.other(value))
        }
      }

      Picker(
        String(localized: .app(.customFields)),
        selection: $filterModel.filterState.sortField
      ) {
        ForEach(customFields, id: \.rawValue) { f in
          Text(f.localizedName(customFields: store.customFields)).tag(f)
        }
      }
      .pickerStyle(.menu)
    } label: {
      Pill(active: !filterModel.filterState.defaultSorting) {
        Label(String(localized: .app(.sortMenuLabel)), systemImage: "arrow.up.arrow.down")
          .labelStyle(.iconOnly)
      }
    }
    .backport.glassEffect(.regular.interactive())
    .onTapGesture {
      Haptics.shared.impact(style: .light)
    }
  }
}

struct FilterBar: View {
  @EnvironmentObject private var store: DocumentStore
  @Environment(FilterModel.self) private var filterModel
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

  @State private var savedView: ProtoSavedView? = nil

  @Namespace private var transition

  private struct Modal<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    var title: String
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
    @Environment(FilterModel.self) private var filterModel

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
            Button(String(localized: .app(.cancel))) {
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
          switch filterModel.filterState.tags {
          case .any:
            Text(.app(.tags))
          case .notAssigned:
            Text(.app(.tagsNotAssignedFilter))
          case .allOf(let include, let exclude):
            let count = include.count + exclude.count
            if count == 1 {
              if let i = include.first, let name = store.tags[i]?.name {
                Text(name)
              } else if let i = exclude.first, let name = store.tags[i]?.name {
                Label(String(localized: .app(.tagExclude)), systemImage: "xmark")
                  .labelStyle(.iconOnly)
                Text(name)
              } else {
                Text(.app(.numberOfTags(1)))
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
              Text(.app(.tags))
            }
          case .anyOf(let ids):
            if ids.count == 1 {
              if let name = store.tags[ids.first!]?.name {
                Text(name)
              } else {
                Text(.app(.numberOfTags(1)))
                  .redacted(reason: .placeholder)
              }
            } else {
              CircleCounter(value: ids.count)
              Text(.app(.tags))
            }
          }
        }

        .backport.matchedTransitionSource(
          id: TransitionKeys.tags, in: transition
        )
      }, active: filterModel.filterState.tags != .any
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
        let text = String(localized: .app(.ownerAll))
        if filterModel.filterState.owner == .any {
          Label(text, systemImage: "checkmark")
        } else {
          Text(text)
        }
      }

      if let user = store.currentUser {
        Button {
          filterModel.filterState.owner = .anyOf(ids: [user.id])
        } label: {
          let text = String(localized: .app(.ownerMyDocuments))
          switch filterModel.filterState.owner {
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
          let text = String(localized: .app(.ownerSharedWithMe))
          switch filterModel.filterState.owner {
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
        let text = String(localized: .app(.ownerUnowned))
        if filterModel.filterState.owner == .notAssigned {
          Label(text, systemImage: "checkmark")
        } else {
          Text(text)
        }
      }

      switch filterModel.filterState.owner {
      case .anyOf(let ids), .noneOf(let ids):
        if ids.count > 1 || (ids.count == 1 && ids[0] != store.currentUser?.id) {
          Divider()
          Text(String(localized: .app(.ownerFilterExplicitUnsupported)))
        } else {
          EmptyView()
        }
      case .notAssigned, .any:
        EmptyView()
      }
    } label: {
      content()
    }
    .backport.glassEffect(.regular.interactive())
  }

  private var ownerElement: some View {
    Pill(active: filterModel.filterState.owner != .any) {
      switch filterModel.filterState.owner {
      case .any:
        Text(.app(.permissions))
      case .anyOf(let ids):
        if ids.count == 1, ids[0] == store.currentUser?.id {
          Text(.app(.ownerMyDocuments))
        } else {
          CircleCounter(value: ids.count, mode: .include)
          Text(.app(.ownerMultipleUsers))
        }
      case .noneOf(let ids):
        if ids.count == 1, ids[0] == store.currentUser?.id {
          Text(.app(.ownerSharedWithMe))
        } else {
          CircleCounter(value: ids.count, mode: .exclude)
          Text(.app(.ownerMultipleUsers))
        }
      case .notAssigned:
        Text(.app(.ownerUnowned))
      }
    }
    .transaction { $0.animation = nil }
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
    @Bindable var filterModel = filterModel
    switch component {
    case .tags:
      tagElement
        .filterPopover(isPresented: $showTags) {
          Modal(title: String(localized: .app(.tags))) {
            TagFilterView(
              selectedTags: $filterModel.filterState.tags)
          }
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.tags, in: transition)
        }
    case .documentType:
      Element(
        label: {
          CommonElementLabel(
            DocumentType.self,
            state: filterModel.filterState.documentType
          )
          .backport.matchedTransitionSource(
            id: TransitionKeys.documentType, in: transition
          )
        }, active: filterModel.filterState.documentType != .any
      ) { present(.documentType) }
      .filterPopover(isPresented: $showDocumentType) {
        Modal(title: String(localized: .app(.documentType))) {
          CommonPickerFilterView(
            selection: $filterModel.filterState.documentType,
            elements: store.documentTypes.sorted {
              $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending
            }.map { ($0.value.id, $0.value.name) },
            notAssignedLabel: String(localized: .app(.documentTypeNotAssignedPicker))
          )
        }
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.documentType, in: transition)
      }
    case .correspondent:
      Element(
        label: {
          CommonElementLabel(
            Correspondent.self,
            state: filterModel.filterState.correspondent
          )
          .backport.matchedTransitionSource(
            id: TransitionKeys.correspondent, in: transition
          )
        }, active: filterModel.filterState.correspondent != .any
      ) { present(.correspondent) }
      .filterPopover(isPresented: $showCorrespondent) {
        Modal(title: String(localized: .app(.correspondent))) {
          CommonPickerFilterView(
            selection: $filterModel.filterState.correspondent,
            elements: store.correspondents.sorted {
              $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending
            }.map { ($0.value.id, $0.value.name) },
            notAssignedLabel: String(localized: .app(.correspondentNotAssignedPicker))
          )
        }
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.correspondent, in: transition)
      }
    case .storagePath:
      Element(
        label: {
          CommonElementLabel(
            StoragePath.self,
            state: filterModel.filterState.storagePath
          )
          .backport.matchedTransitionSource(
            id: TransitionKeys.storagePath, in: transition
          )
        }, active: filterModel.filterState.storagePath != .any
      ) { present(.storagePath) }
      .filterPopover(isPresented: $showStoragePath) {
        Modal(title: String(localized: .app(.storagePath))) {
          CommonPickerFilterView(
            selection: $filterModel.filterState.storagePath,
            elements: store.storagePaths.sorted {
              $0.value.name.localizedCaseInsensitiveCompare($1.value.name) == .orderedAscending
            }.map { ($0.value.id, $0.value.name) },
            notAssignedLabel: String(localized: .app(.storagePathNotAssignedPicker))
          )
        }
        .backport.navigationTransitionZoom(sourceID: TransitionKeys.storagePath, in: transition)
      }
    case .permissions:
      ownerMenu {
        ownerElement
      }
      .onTapGesture {
        Haptics.shared.impact(style: .light)
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
      .filterPopover(isPresented: $showCustomFields) {
        CustomFieldFilterView(query: $filterModel.filterState.customField)
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.customFields, in: transition)
      }
    case .asn:
      Element(
        label: {
          AsnFilterDisplayView(query: filterModel.filterState.asn)
            .backport.matchedTransitionSource(
              id: TransitionKeys.asn, in: transition
            )
        }, active: filterModel.filterState.asn != .any
      ) { present(.asn) }
      .filterPopover(isPresented: $showAsn) {
        AsnFilterView(query: $filterModel.filterState.asn)
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.asn, in: transition)
      }
    case .date:
      Element(
        label: {
          DateFilterDisplayView(query: filterModel.filterState.date)
            .backport.matchedTransitionSource(
              id: TransitionKeys.date, in: transition
            )
        }, active: filterModel.filterState.date.isActive
      ) { present(.date) }
      .filterPopover(isPresented: $showDate) {
        DateFilterView(query: $filterModel.filterState.date)
          .backport.navigationTransitionZoom(sourceID: TransitionKeys.date, in: transition)
      }
    }
  }

  private var barContent: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack {
        FilterMenu(savedView: $savedView) {
          Pill(
            active: filterModel.filterState.filtering || filterModel.filterState.savedView != nil,
            chevron: false
          ) {
            Label(
              String(localized: .app(.filtering)), systemImage: "line.3.horizontal.decrease"
            )
            .labelStyle(.iconOnly)
            if filterModel.filterState.filtering {
              CircleCounter(value: filterModel.filterState.defaultAwareRuleCount)
            }
          }
        }

        ForEach(configuredComponents, id: \.self) { component in
          componentView(component)
        }

        Divider()

        SortMenu()
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
    @Bindable var filterModel = filterModel

    barView
      .scaledToFit()
      .padding(.vertical, 5)

      .onChange(of: routeManager.pendingRoute, initial: true, handlePendingRoute)

      .sheet(item: $savedView) { view in
        AddSavedViewSheet(savedView: view)
      }

  }
}

extension View {
  /// Presents the filter editor anchored to the source pill. Renders as a
  /// popover on regular size class (iPad) and adapts back to a sheet on
  /// compact (iPhone) via `presentationCompactAdaptation(.sheet)`.
  ///
  /// `popoverSize` only affects the popover layer — the adapted sheet
  /// ignores it and lays out at full height.
  fileprivate func filterPopover<Content: View>(
    isPresented: Binding<Bool>,
    popoverSize: CGSize = CGSize(width: 420, height: 520),
    @ViewBuilder content: @escaping () -> Content
  ) -> some View {
    popover(isPresented: isPresented) {
      content()
        .frame(idealWidth: popoverSize.width, idealHeight: popoverSize.height)
        .presentationCompactAdaptation(.sheet)
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
  @Previewable @State var filterModel = FilterModel()
  @Previewable @StateObject var errorController = ErrorController()

  NavigationStack {
    Form {
      FilterBar()
        .environmentObject(store)
        .environment(filterModel)
        .environmentObject(errorController)
        .environment(RouteManager())

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
