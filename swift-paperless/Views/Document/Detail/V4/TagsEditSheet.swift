//
//  TagsEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import DataModel
import Networking
import SwiftUI

private let tagsEditDisplayLimit = 200

struct TagsEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss

  @State private var tagIds: [UInt]
  @State private var searchText = ""
  @State private var searchIsActive: Bool
  @State private var selectedDetent: PresentationDetent
  @State private var saving = false
  @State private var showCreateTag = false
  @State private var sortedTags: [Tag] = []
  @Namespace private var tagNamespace

  init(viewModel: DocumentDetailModel) {
    self.viewModel = viewModel
    let noTags = viewModel.document.tags.isEmpty
    _tagIds = State(initialValue: viewModel.document.tags)
    _searchIsActive = State(initialValue: noTags)
    _selectedDetent = State(initialValue: noTags ? .large : .medium)
  }

  private struct CreateTagView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Tag) -> Void

    var body: some View {
      TagEditView<ProtoTag>(onSave: { value in
        Task {
          do {
            let tag = try await store.create(tag: value)
            onCreated(tag)
            dismiss()
          } catch {
            errorController.push(error: error)
          }
        }
      })
      .navigationTitle(Text(.localizable(.tagCreateTitle)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var interactiveDismissDisabled: Bool {
    tagIds != viewModel.document.tags
  }

  private var suggestedTags: [Tag] {
    (viewModel.suggestions.tags)
      .filter { !tagIds.contains($0) }
      .compactMap { store.tags[$0] }
  }

  private func sortedByName(_ values: some Collection<Tag>) -> [Tag] {
    values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func computeAvailable() -> (entries: [(tag: Tag, depth: Int)], total: Int) {
    let selected = Set(tagIds)
    let search = searchText
    var matched: [Tag] = []
    matched.reserveCapacity(sortedTags.count)
    for tag in sortedTags {
      if selected.contains(tag.id) { continue }
      if !search.isEmpty, !tag.name.localizedCaseInsensitiveContains(search) { continue }
      matched.append(tag)
    }

    // While searching, keep results flat (depth 0) so cross-tree matches stay
    // grouped together. Otherwise lay out children right under their parents.
    let entries: [(tag: Tag, depth: Int)]
    if search.isEmpty, matched.contains(where: { $0.parent != nil }) {
      let visibleIds = Set(matched.map(\.id))
      var byParent: [UInt?: [Tag]] = [:]
      for tag in matched {
        let key: UInt? = tag.parent.flatMap { visibleIds.contains($0) ? $0 : nil }
        byParent[key, default: []].append(tag)
      }
      var dfs: [(tag: Tag, depth: Int)] = []
      dfs.reserveCapacity(matched.count)
      func walk(_ parent: UInt?, depth: Int) {
        for tag in byParent[parent] ?? [] {
          dfs.append((tag, depth))
          walk(tag.id, depth: depth + 1)
        }
      }
      walk(nil, depth: 0)
      entries = dfs
    } else {
      entries = matched.map { (tag: $0, depth: 0) }
    }

    let limited = Array(entries.prefix(tagsEditDisplayLimit))
    return (limited, matched.count)
  }

  private func save() {
    Task {
      do {
        saving = true
        viewModel.document.tags = tagIds
        try await viewModel.updateDocument()
        saving = false
        dismiss()
      } catch {
        saving = false
        errorController.push(error: error)
      }
    }
  }

  private func add(_ tag: UInt) {
    // Mirror backend behavior: attaching a child tag implicitly attaches
    // every ancestor along its parent chain.
    let toAdd = [tag] + store.tagAncestors(of: tag)
    let existing = Set(tagIds)
    let new = toAdd.filter { !existing.contains($0) }
    guard !new.isEmpty else { return }
    withAnimation(animation) {
      tagIds.append(contentsOf: new)
    }
  }

  private func remove(_ tag: UInt) {
    // Mirror backend behavior: detaching a tag also detaches every descendant.
    let toRemove = store.tagDescendants(of: tag).union([tag])
    withAnimation(animation) {
      tagIds.removeAll { toRemove.contains($0) }
    }
  }

  let animation = Animation.spring(duration: 0.2)

  var body: some View {
    let available = computeAvailable()
    return NavigationStack {
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          CustomSection {
            VStack(alignment: .leading, spacing: 0) {
              if tagIds.isEmpty {
                CustomSectionRow {
                  Text(.localizable(.noTagsSelected))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                }
              } else {
                CustomSectionRow {
                  HFlow {
                    ForEach(tagIds, id: \.self) { tagId in
                      Button {
                        remove(tagId)
                      } label: {
                        TagView(tag: store.tags[tagId]) {
                          Image(systemName: "xmark")
                            .font(.caption2)
                            .fontWeight(.bold)
                        }
                        .fixedSize()
                        .matchedGeometryEffect(id: tagId, in: tagNamespace)
                      }
                      .buttonStyle(.plain)
                      .transition(.opacity)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .topLeading)
                }
              }

              if !suggestedTags.isEmpty {
                SuggestionsRow {
                  ForEach(suggestedTags, id: \.id) { tag in
                    Button {
                      add(tag.id)
                    } label: {
                      TagView(tag: tag)
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                  }
                }
              }
            }
          }

          if !available.entries.isEmpty {
            CustomSection {
              VStack(spacing: 0) {
                ForEach(Array(available.entries.enumerated()), id: \.element.tag.id) {
                  index, entry in
                  Button {
                    add(entry.tag.id)
                  } label: {
                    CustomSectionRow {
                      HStack {
                        TagView(tag: entry.tag)
                          .fixedSize()
                          .matchedGeometryEffect(id: entry.tag.id, in: tagNamespace)
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                          .foregroundStyle(.secondary)
                      }
                      .padding(.leading, CGFloat(entry.depth) * 16)
                    }
                  }
                  .buttonStyle(.plain)
                  .transition(.opacity)

                  if index < available.entries.count - 1 {
                    Divider()
                  }
                }
              }
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
      .navigationTitle(.localizable(.tags))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            showCreateTag = true
          } label: {
            Label(String(localized: .localizable(.tagAdd)), systemImage: "plus")
          }
          .disabled(!store.permissions.test(.add, for: .tag))
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            SaveButton {
              save()
            }
            .fontWeight(.bold)
            .disabled(tagIds == viewModel.document.tags)
          }
        }
      }
    }
    .presentationDetents([.medium, .large], selection: $selectedDetent)
    .interactiveDismissDisabled(interactiveDismissDisabled)
    .onAppear {
      if sortedTags.isEmpty {
        sortedTags = sortedByName(store.tags.values)
      }
    }
    .onChange(of: store.tags.count) { _, _ in
      sortedTags = sortedByName(store.tags.values)
    }
    .sheet(isPresented: $showCreateTag) {
      NavigationStack {
        CreateTagView(onCreated: { tag in
          tagIds.append(tag.id)
        })
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            CancelIconButton()
          }
        }
      }
    }
  }
}
