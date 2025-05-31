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
struct TagFilterView: View {
    @EnvironmentObject private var store: DocumentStore

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    private enum Mode {
        case all
        case any
    }

    @Binding var selectedTags: FilterState.TagFilter
    @State private var mode = Mode.all

    init(selectedTags: Binding<FilterState.TagFilter>) {
        _selectedTags = selectedTags
        switch self.selectedTags {
        case .anyOf:
            _mode = State(initialValue: Mode.any)
        case .allOf:
            _mode = State(initialValue: Mode.all)
        default: break
        }
    }

    private func row(action: @escaping () -> Void,
                     active: Bool,
                     @ViewBuilder content: () -> some View) -> some View
    {
        HStack {
            Button(action: { withAnimation { action() }}, label: content)
                .foregroundColor(.primary)
            Spacer()
            if active {
                Label(String(localized: .localizable(.tagIsSelected)), systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func tagFilter(tag: Tag) -> Bool {
        if searchDebounce.debouncedText.isEmpty { return true }
        if let _ = tag.name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) {
            return true
        } else {
            return false
        }
    }

    private func onPress(tag: Tag) {
        var next: FilterState.TagFilter = selectedTags

        switch selectedTags {
        case .any:
            next = .allOf(include: [tag.id], exclude: [])

        case .notAssigned:
            next = .allOf(include: [tag.id], exclude: [])

        case let .allOf(include, exclude):
            if include.contains(tag.id) {
                next = .allOf(
                    include: include.filter { $0 != tag.id },
                    exclude: exclude + [tag.id]
                )
            } else if exclude.contains(tag.id) {
                next = .allOf(
                    include: include,
                    exclude: exclude.filter { $0 != tag.id }
                )
            } else {
                next = .allOf(
                    include: include + [tag.id],
                    exclude: exclude
                )
            }

        case let .anyOf(ids):
            if ids.contains(tag.id) {
                next = .anyOf(ids: ids.filter { $0 != tag.id })
            } else {
                next = .anyOf(ids: ids + [tag.id])
            }
        }

        switch next {
        case let .allOf(include, exclude):
            if include.isEmpty, exclude.isEmpty {
                next = .any
            }
            if !exclude.isEmpty {
                mode = .all
            }
        case let .anyOf(ids):
            if ids.isEmpty {
                next = .any
            }
        default:
            break
        }

        withAnimation {
            selectedTags = next
        }
    }

    private var sortedTags: [Tag] {
        store.tags.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack {
            VStack {
                SearchBarView(text: $searchDebounce.text)
            }
            .transition(.opacity)
            .padding(.horizontal)
            .padding(.vertical, 2)

            Form {
                Section {
                    row(action: {
                        Task { withAnimation { selectedTags = .any }}
                    }, active: selectedTags == .any, content: {
                        Text(.localizable(.tagsFilterAny))
                    })

                    row(action: {
                        Task { withAnimation { selectedTags = .notAssigned }}
                    }, active: selectedTags == .notAssigned, content: {
                        Text(.localizable(.tagsNotAssignedPicker))
                    })
                }

                Section {
                    ForEach(
                        sortedTags
                            .filter { tagFilter(tag: $0) },
                        id: \.id
                    ) { tag in
                        HStack {
                            Button(action: { onPress(tag: tag) }) {
                                TagView(tag: tag)
                            }

                            Spacer()

                            VStack {
                                let empty = Label(String(localized: .localizable(.tagIsNotSelected)), systemImage: "circle")
                                    .labelStyle(.iconOnly)
                                switch selectedTags {
                                case .any:
                                    empty
                                case .notAssigned:
                                    empty
                                case let .allOf(include, exclude):
                                    if include.contains(tag.id) {
                                        Label(String(localized: .localizable(.tagIncluded)), systemImage: "checkmark.circle")
                                            .labelStyle(.iconOnly)
                                    } else if exclude.contains(tag.id) {
                                        Label(String(localized: .localizable(.tagExcluded)), systemImage: "xmark.circle")
                                            .labelStyle(.iconOnly)
                                    } else {
                                        empty
                                    }
                                case let .anyOf(ids):
                                    if ids.contains(tag.id) {
                                        Label(String(localized: .localizable(.tagIsSelected)), systemImage: "checkmark.circle")
                                            .labelStyle(.iconOnly)
                                    } else {
                                        empty
                                    }
                                }
                            }
                            .frame(width: 20, alignment: .trailing)
                        }
                        .transaction { transaction in transaction.animation = nil }
                    }
                } header: {
                    Picker("Tag filter mode", selection: $mode) {
                        Text(.localizable(.tagsAll)).tag(Mode.all)
                        Text(.localizable(.tagsAny)).tag(Mode.any)
                    }
                    .textCase(.none)
                    .padding(.bottom, 10)
                    .pickerStyle(.segmented)
                    .disabled({
                        switch selectedTags {
                        case .any:
                            true
                        case .notAssigned:
                            true
                        case let .allOf(_, exclude):
                            !exclude.isEmpty
                        case .anyOf:
                            false
                        }
                    }())
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color(.divider))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }

        .onChange(of: mode) { _, value in
            switch value {
            case .all:
                switch selectedTags {
                case .allOf:
                    break // already in all
                case let .anyOf(ids):
                    selectedTags = .allOf(include: ids, exclude: [])
                default:
                    print("Switched to Mode.all in invalid state")
                }
            case .any:
                switch selectedTags {
                case let .allOf(include, exclude):
                    if !exclude.isEmpty {
                        print("Switched to Mode.any, but had excludes??")
                    }
                    selectedTags = .anyOf(ids: include)
                case .anyOf:
                    break // already in any
                default:
                    print("Switched to Mode.any in invalid state")
                }
            }
        }
    }
}

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

    private func row(action: @escaping () -> Void,
                     active: Bool,
                     @ViewBuilder content: () -> some View) -> some View
    {
        HStack {
            Button(action: { withAnimation { action() }}, label: content)
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
        if let _ = tag.name.range(of: searchText, options: .caseInsensitive) {
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

    private struct NoElementsView: View {
        var body: some View {
            ContentUnavailableView(String(localized: .localizable(.noElementsFound)),
                                   systemImage: "exclamationmark.magnifyingglass",
                                   description: Text(Tag.localizedNamePlural))
        }
    }

    private struct NoPermissionsView: View {
        var body: some View {
            ContentUnavailableView(String(localized: .permissions(.noViewPermissionsDisplayTitle)),
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
                    ForEach(displayTags, id: \.id) { tag in
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
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText)

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

// MARK: - Previews

private struct BindingHelper<Element, Content: View>: View {
    @State var element: Element
    @ViewBuilder var content: (Binding<Element>) -> Content

    var body: some View {
        content($element)
    }
}

struct TagFilterView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    @State static var filterState = FilterState.default

    static var previews: some View {
        BindingHelper(element: filterState.tags) { tags in
            TagFilterView(selectedTags: tags)
        }
        .environmentObject(store)
    }
}
