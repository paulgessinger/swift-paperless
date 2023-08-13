//
//  FilterBar.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 10.04.23.
//

import Combine
import Foundation
import os
import SwiftUI
import SwiftUINavigation

// @TODO: Add UI for FilterState with remaining rules!

// MARK: FilterMenu

extension ProtoSavedView: Identifiable {
    var id: UInt { return 0 }
}

private struct SavedViewError: LocalizedError {
    var errorDescription: String? {
        return "Active SavedView was not found in store and could not be saved"
    }
}

private struct FilterMenu<Content: View>: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var filterModel: FilterModel
    @EnvironmentObject private var errorController: ErrorController
    @Binding var filterState: FilterState
    @Binding var savedView: ProtoSavedView?
    @ViewBuilder var label: () -> Content

//    @State private var savedView: ProtoSavedView? = nil

    @State private var showDeletePrompt = false

    func saveSavedView(_ savedView: SavedView) {
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
            }
            catch {
                print(error)
            }
        }
    }

    var body: some View {
        VStack {
            Menu {
                Text("Saved views")
                if !store.savedViews.isEmpty {
                    ForEach(store.savedViews.map { $0.value }.sorted { $0.name < $1.name }, id: \.id) { savedView in
                        if filterModel.filterState.savedView == savedView.id {
                            Menu {
                                if filterModel.filterState.modified {
                                    Button("Save") { saveSavedView(savedView) }
                                    Button {
                                        filterModel.filterState = .init(savedView: savedView)
                                    } label: {
                                        Label("Discard changes", systemImage: "arrow.counterclockwise")
                                    }
                                }
                                Button("Delete", role: .destructive) {
                                    showDeletePrompt = true
                                }
                            } label: {
                                if filterModel.filterState.modified {
                                    Label(String(localized: "\(savedView.name) (modified)", comment: "Indicates a saved view has been modified"), systemImage: "checkmark")
                                }
                                else {
                                    Label(savedView.name, systemImage: "checkmark")
                                }
                            }
                        }
                        else {
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    filterModel.filterState = .init(savedView: savedView)
                                }
                            } label: {
                                Text(savedView.name)
                            }
                        }
                    }
                }

                Divider()
                if filterState.filtering && (filterState.savedView == nil || filterState.modified) {
                    Button {
                        let proto = ProtoSavedView(
                            name: "",
                            sortField: filterModel.filterState.sortField,
                            sortOrder: filterModel.filterState.sortOrder,
                            filterRules: filterModel.filterState.rules
                        )

                        savedView = proto
                        //                    showSavedViewModal = true

                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                }

                NavigationLink {
                    ManageView<SavedViewManager>(store: store)
                        .navigationTitle("Saved views")
                        .task { Task.detached { await store.fetchAllDocumentTypes() }}
                } label: {
                    Label(String(localized: "Edit saved views", comment: "Saved view edit menu button"), systemImage: "list.bullet")
                }

                if filterState.filtering {
                    if !store.savedViews.isEmpty {
                        Divider()
                    }
                    Text("\(filterState.ruleCount) filter(s) applied")
                    Divider()
                    Button(role: .destructive) {
                        Haptics.shared.notification(.success)
                        withAnimation {
                            filterModel.filterState.clear()
                            filterState.clear()
                        }
                    } label: {
                        Label(String(localized: "Clear filters"), systemImage: "xmark")
                    }
                }

            } label: {
                label()
            }
        }

        .alert("Delete saved view", isPresented: $showDeletePrompt,
               presenting: filterState.savedView,
               actions: { id in
                   Button("Delete", role: .destructive) {
                       Task {
                           do {
                               filterModel.filterState.savedView = nil
                               try? await Task.sleep(for: .seconds(0.2))
                               try await store.delete(savedView: store.savedViews[id]!)
                           }
                           catch {
                               print("Error deleting view")
                               filterModel.filterState.savedView = id
                           }
                       }
                   }
               }, message: { id in
                   let sv = store.savedViews[id]!
                   Text("Are you sure you want to delete '\(sv.name)'")
               })
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
            return Color.accentColor
        case .exclude:
            return Color.red
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

    init(_ type: Element.Type, state: FilterState.Filter) {
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
                }
                else {
                    Text(Element.singularLabel)
                        .redacted(reason: .placeholder)
                }
            }
            else {
                CircleCounter(value: ids.count, mode: .include)
                Text(Element.pluralLabel)
            }
        case .noneOf(let ids):
            if ids.count == 1 {
                Label(Element.excludeLabel, systemImage: "xmark")
                    .labelStyle(.iconOnly)
                if let name = store[keyPath: Element.storePath][ids[0]]?.name {
                    Text(name)
                }
                else {
                    Text(Element.singularLabel)
                        .redacted(reason: .placeholder)
                }
            }
            else {
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
                .fill(Color("ElementBackground"))
        }
        .overlay(
            Capsule()
                .strokeBorder(active ? Color("AccentColorLightened") : Color("ElementBorder"),
                              lineWidth: 1))
        .foregroundColor(active ? Color("AccentColorLightened") : Color.primary)
        .if(active) { view in view.bold() }
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

    private enum ModalMode {
        case tags
        case correspondent
        case documentType
        case storagePath
    }

    @State private var filterState = FilterState()

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
                        Button(String(localized: "Done")) {
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
                        }
                        catch {
                            print(error)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
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
                    Label(String(localized: "Filtering", comment: "Filter bar extra menu label"), systemImage: "line.3.horizontal.decrease")
                        .labelStyle(.iconOnly)
                    if let savedViewId = filterState.savedView,
                       let savedView = store.savedViews[savedViewId]
                    {
                        if filterState.modified {
                            Text(String(localized: "\(savedView.name)*", comment: "Indicates modified saved view in the filter bar"))
                        }
                        else {
                            Text(savedView.name)
                        }
                    }
                    else if filterState.ruleCount > 0 {
                        CircleCounter(value: filterState.ruleCount)
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

                .onChange(of: offset) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation {
                            menuWidth = offset.width
                        }
                    }
                }

                Element(label: {
                    switch filterState.tags {
                    case .any:
                        Text("Tags")
                    case .notAssigned:
                        Text(LocalizedStrings.Filter.Tags.notAssignedFilter)
                    case .allOf(let include, let exclude):
                        let count = include.count + exclude.count
                        if count == 1 {
                            if let i = include.first, let name = store.tags[i]?.name {
                                Text(name)
                            }
                            else if let i = exclude.first, let name = store.tags[i]?.name {
                                Label("Exclude tag", systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                                Text(name)
                            }
                            else {
                                Text(String(localized: "\(1) tag(s)"))
                                    .redacted(reason: .placeholder)
                            }
                        }
                        else {
                            if !include.isEmpty, !exclude.isEmpty {
                                CircleCounter(value: include.count, mode: .include)
                                Text(String("/"))
                                CircleCounter(value: exclude.count, mode: .exclude)
                            }
                            else if !include.isEmpty {
                                CircleCounter(value: count, mode: .include)
                            }
                            else {
                                CircleCounter(value: count, mode: .exclude)
                            }
                            Text("Tags")
                        }
                    case .anyOf(let ids):
                        if ids.count == 1 {
                            if let name = store.tags[ids.first!]?.name {
                                Text(name)
                            }
                            else {
                                Text(String(localized: "\(1) tag(s)"))
                                    .redacted(reason: .placeholder)
                            }
                        }
                        else {
                            CircleCounter(value: ids.count)
                            Text("Tags")
                        }
                    }
                }, active: filterState.tags != .any) {
                    present(.tags)
                }

                Element(label: {
                    CommonElementLabel(DocumentType.self,
                                       state: filterState.documentType)
                }, active: filterState.documentType != .any) { present(.documentType) }

                Element(label: {
                    CommonElementLabel(Correspondent.self,
                                       state: filterState.correspondent)
                }, active: filterState.correspondent != .any) { present(.correspondent) }

                Element(label: {
                    CommonElementLabel(StoragePath.self,
                                       state: filterState.storagePath)
                }, active: filterState.storagePath != .any) { present(.storagePath) }

                Pill(active: filterState.owner != .any) {
                    switch filterState.owner {
                    case .any:
                        Text("Permissions")
                    case .anyOf(let ids):
                        if ids.count == 1 && ids[0] == store.currentUser?.id {
                            Text(LocalizedStrings.Filter.Owner.myDocuments)
                        }
                        else {
                            CircleCounter(value: ids.count, mode: .include)
                            Text(LocalizedStrings.Filter.Owner.multipleUsers)
                        }
                    case .noneOf(let ids):
                        if ids.count == 1 && ids[0] == store.currentUser?.id {
                            Text(LocalizedStrings.Filter.Owner.sharedWithMe)
                        }
                        else {
                            CircleCounter(value: ids.count, mode: .exclude)
                            Text(LocalizedStrings.Filter.Owner.multipleUsers)
                        }
                    case .notAssigned:
                        Text(LocalizedStrings.Filter.Owner.unowned)
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
                                let text = LocalizedStrings.Filter.Owner.all
                                if filterState.owner == .any {
                                    Label(text, systemImage: "checkmark")
                                }
                                else {
                                    Text(text)
                                }
                            }

                            if let user = store.currentUser {
                                Button {
                                    withAnimation {
                                        filterModel.filterState.owner = .anyOf(ids: [user.id])
                                    }
                                } label: {
                                    let text = LocalizedStrings.Filter.Owner.myDocuments
                                    switch filterState.owner {
                                    case .anyOf(let ids):
                                        if ids.count == 1 && ids[0] == store.currentUser?.id {
                                            Label(text, systemImage: "checkmark")
                                        }
                                        else {
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
                                    let text = LocalizedStrings.Filter.Owner.sharedWithMe
                                    switch filterState.owner {
                                    case .noneOf(let ids):
                                        if ids.count == 1 && ids[0] == store.currentUser?.id {
                                            Label(text, systemImage: "checkmark")
                                        }
                                        else {
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
                                let text = LocalizedStrings.Filter.Owner.unowned
                                if filterState.owner == .notAssigned {
                                    Label(text, systemImage: "checkmark")
                                }
                                else {
                                    Text(text)
                                }
                            }

                            switch filterState.owner {
                            case .anyOf(let ids), .noneOf(let ids):
                                if ids.count > 1 || (ids.count == 1 && ids[0] != store.currentUser?.id) {
                                    Divider()
                                    Text(String(localized: "owner_filter_explicit_unsupported", comment: "Filter state additional information popup"))
                                }
                                else {
                                    EmptyView()
                                }
                            case .notAssigned, .any:
                                EmptyView()
                            }
                        } label: {
                            Color.clear
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }

                Divider()

                Menu {
                    Picker("Sort by", selection: $filterState.sortField) {
                        ForEach(SortField.allCases, id: \.rawValue) { f in
                            Text(f.label).tag(f)
                        }
                    }

                    Picker("Sort ordering", selection: $filterState.sortOrder) {
                        Label("Ascending", systemImage: "arrow.up")
                            .tag(SortOrder.ascending)
                        Label("Descending", systemImage: "arrow.down")
                            .tag(SortOrder.descending)
                    }
                }
                label: {
                    Element(label: {
                        Label("Sort menu", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.iconOnly)
                    }, active: filterState.sortOrder != .descending || filterState.sortField != .added, action: {})
                }
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

        .onChange(of: filterState.sortOrder) { value in
            filterModel.filterState.sortOrder = value
        }

        .onChange(of: filterState.sortField) { value in
            filterModel.filterState.sortField = value
        }

        // MARK: Sheets

        .sheet(isPresented: $showTags) {
            Modal(title: String(localized: "Tags"), filterState: $filterState) {
                TagFilterView(
                    selectedTags: $filterState.tags)
            }
        }

        .sheet(isPresented: $showDocumentType) {
            Modal(title: String(localized: "Document type"), filterState: $filterState) {
                CommonPicker(
                    selection: $filterState.documentType,
                    elements: store.documentTypes.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) },
                    notAssignedLabel: LocalizedStrings.Filter.DocumentType.notAssignedPicker
                )
            }
        }

        .sheet(isPresented: $showCorrespondent) {
            Modal(title: String(localized: "Correspondent"), filterState: $filterState) {
                CommonPicker(
                    selection: $filterState.correspondent,
                    elements: store.correspondents.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) },
                    notAssignedLabel: LocalizedStrings.Filter.Correspondent.notAssignedPicker
                )
            }
        }

        .sheet(isPresented: $showStoragePath) {
            Modal(title: String(localized: "Storage path"), filterState: $filterState) {
                CommonPicker(
                    selection: $filterState.storagePath,
                    elements: store.storagePaths.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) },
                    notAssignedLabel: LocalizedStrings.Filter.StoragePath.notAssignedPicker
                )
            }
        }

        .sheet(unwrapping: self.$savedView) { $view in
            AddSavedViewSheet(savedView: view)
        }

        .onReceive(filterModel.filterStatePublisher) { value in
            DispatchQueue.main.async {
                withAnimation {
                    filterState = value
                }
            }
        }
    }
}
