//
//  TagsEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import DataModel
import Networking
import SwiftUI

struct TagsEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss

  @State private var tagIds: [UInt] = []
  @State private var searchText = ""
  @State private var saving = false
  @State private var showCreateTag = false
  @Namespace private var tagNamespace

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

  private var availableTags: [Tag] {
    let search = searchText.lowercased()
    return store.tags.values
      .filter { !tagIds.contains($0.id) }
      .filter { search.isEmpty || $0.name.lowercased().contains(search) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    withAnimation(animation) {
      tagIds.append(tag)
    }
  }

  private func remove(_ tag: UInt) {
    withAnimation(animation) {
      tagIds.removeAll { $0 == tag }
    }
  }

  let animation = Animation.spring(duration: 0.2)

  var body: some View {
    NavigationStack {
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

          VStack(spacing: 0) {
            if !availableTags.isEmpty {
              CustomSection {
                VStack(spacing: 0) {
                  ForEach(Array(availableTags.enumerated()), id: \.element.id) { index, tag in
                    Button {
                      add(tag.id)
                    } label: {
                      CustomSectionRow {
                        HStack {
                          TagView(tag: tag)
                            .fixedSize()
                            .matchedGeometryEffect(id: tag.id, in: tagNamespace)
                          Spacer()
                          Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.secondary)
                        }
                      }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)

                    if index < availableTags.count - 1 {
                      Divider()
                    }
                  }
                }
              }
            }
          }
          .animation(animation, value: availableTags.isEmpty)
        }
      }
      .customSectionBackground(.thickMaterial)
      .scrollBounceBehavior(.basedOnSize)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
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
    .interactiveDismissDisabled(interactiveDismissDisabled)
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
    .onAppear {
      tagIds = viewModel.document.tags
    }
  }
}
