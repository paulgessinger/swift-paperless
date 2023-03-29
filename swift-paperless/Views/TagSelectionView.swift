//
//  TagSelectionView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.03.23.
//

import SwiftUI

struct TagSelectionView: View {
    var tags: [UInt: Tag]
    @Binding var selectedTags: FilterState.Tag
    var filterMode = true

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    private func row<Content: View>(action: @escaping () -> (),
                                    active: Bool,
                                    @ViewBuilder content: () -> Content) -> some View
    {
        HStack {
            Button(action: { withAnimation { action() }}, label: content)
                .foregroundColor(.primary)
            Spacer()
            if active {
                Label("Active", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private func tagFilter(tag: Tag) -> Bool {
        if searchDebounce.debouncedText.isEmpty { return true }
        if let _ = tag.name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) {
            return true
        }
        else {
            return false
        }
    }

    var body: some View {
        VStack {
            VStack {
                if case var .only(ids) = selectedTags {
                    TagsView(tags: ids.compactMap { tags[$0] }) { tag in
                        Task {
                            withAnimation {
                                if let i = ids.firstIndex(of: tag.id) {
                                    ids.remove(at: i)
                                }
                                if filterMode {
                                    selectedTags = ids.isEmpty ? .any : .only(ids: ids)
                                }
                                else {
                                    selectedTags = ids.isEmpty ? .notAssigned : .only(ids: ids)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        Rectangle()
                            .fill(Color.systemGroupedBackground)
                            .cornerRadius(10)
                    )
                    .padding(.bottom, 5)
                }

                // MARK: - Search bar

                SearchBarView(text: $searchDebounce.debouncedText)
            }
            .transition(.opacity)
            .padding(.horizontal)
            .padding(.vertical, 2)

            // MARK: - Tag selection list

            Form {
                Section {
                    if filterMode {
                        row(action: {
                            Task { withAnimation { selectedTags = .any }}
                        }, active: selectedTags == .any, content: {
                            Text("Any")
                        })

                        row(action: {
                            Task { withAnimation { selectedTags = .notAssigned }}
                        }, active: selectedTags == .notAssigned, content: {
                            Text("Not assigned")
                        })
                    }
                    else {
                        // Repurpose not assigned to mean: no tags assigned
                        row(action: {
                            Task { withAnimation { selectedTags = .notAssigned }}
                        }, active: selectedTags == .notAssigned, content: {
                            Text("None")
                        })
                    }
                }

                ForEach(
                    tags.sorted { $0.value.name < $1.value.name }
                        .filter { tagFilter(tag: $0.value) },
                    id: \.value.id
                ) { _, tag in
                    HStack {
                        Button(action: {
                            Task {
                                withAnimation {
                                    switch selectedTags {
                                    case .any, .notAssigned:
                                        selectedTags = .only(ids: [tag.id])
                                    case var .only(ids):
                                        if let i = ids.firstIndex(of: tag.id) {
                                            ids.remove(at: i)
                                        }
                                        else {
                                            ids.append(tag.id)
                                        }

                                        if filterMode {
                                            selectedTags = ids.isEmpty ? .any : .only(ids: ids)
                                        }
                                        else {
                                            selectedTags = ids.isEmpty ? .notAssigned : .only(ids: ids)
                                        }
                                    }
                                }
                            }
                        }) {
                            TagView(tag: tag)
                        }

                        Spacer()

                        if case let .only(ids) = selectedTags {
                            if ids.contains(tag.id) {
                                Label("Active", systemImage: "checkmark")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color("Divider"))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
//            .animation(.linear, value: searchDebounce.debouncedText)
        }
    }
}

// MARK: - Previews

struct TagSelectionView_Previews: PreviewProvider {
    @State static var filterState = FilterState()

    static var previews: some View {
        TagSelectionView(tags: PreviewModel.tags,
                         selectedTags: $filterState.tags,
                         filterMode: true)
    }
}

struct TagSelectionViewEdit_Previews: PreviewProvider {
    @State static var filterState = FilterState()

    static var previews: some View {
        TagSelectionView(tags: PreviewModel.tags,
                         selectedTags: $filterState.tags,
                         filterMode: false)
    }
}
