//
//  TagSelectionView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.03.23.
//

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

    var body: some View {
        VStack {
            VStack {
                SearchBarView(text: $searchDebounce.text)
            }
            .transition(.opacity)
            .padding(.horizontal)
            .padding(.vertical, 2)

            // Debug:
//            Text(String(describing: selectedTags))

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
                        store.tags.sorted { $0.value.name < $1.value.name }
                            .filter { tagFilter(tag: $0.value) },
                        id: \.value.id
                    ) { _, tag in
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

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

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
        if searchDebounce.debouncedText.isEmpty { return true }
        if let _ = tag.name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) {
            return true
        } else {
            return false
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

            // MARK: - Tag selection list

            Form {
                if !document.tags.isEmpty {
                    Section {
                        ForEach(document.tags, id: \.self) { id in
                            let tag = store.tags[id]
                            Button(action: {
                                withAnimation {
                                    document.tags = document.tags.filter { $0 != id }
                                }
                            }) {
                                HStack {
                                    TagView(tag: tag).if(tag == nil) { view in
                                        view.redacted(reason: .placeholder)
                                    }
                                    Spacer()
                                    Label(String(localized: .localizable(.remove)), systemImage: "xmark.circle.fill")
                                        .labelStyle(.iconOnly)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    } header: {
                        Text(.localizable(.selected))
                    }
                }

                Section {
                    ForEach(
                        store.tags.sorted { $0.value.name < $1.value.name }
                            .filter { tagFilter(tag: $0.value) },
                        id: \.value.id
                    ) { _, tag in
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
            .overlay(
                Rectangle()
                    .fill(Color(.divider))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }

        .navigationTitle(Text(.localizable(.tags)))

        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    CreateTag(document: $document)
                } label: {
                    Label(String(localized: .localizable(.tagAdd)), systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Previews

struct TagFilterView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    @State static var filterState = FilterState()

    static var previews: some View {
        BindingHelper(element: filterState.tags) { tags in
            TagFilterView(selectedTags: tags)
        }
        .environmentObject(store)
    }
}
