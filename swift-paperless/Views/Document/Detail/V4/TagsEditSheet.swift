//
//  TagsEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import DataModel
import Flow
import Networking
import SwiftUI

struct TagsEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss

  @Environment(\.sheetDetent) private var sheetDetent

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
    showCreateTag || tagIds != viewModel.document.tags
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
        var document = viewModel.document
        document.tags = tagIds
        let updated = try await store.updateDocument(document)
        viewModel.document = updated
        saving = false
        dismiss()
      } catch {
        saving = false
        errorController.push(error: error)
      }
    }
  }

  let animation = Animation.spring(duration: 0.2)

  var body: some View {
    NavigationStack {
      ScrollView(.vertical) {
        CustomSection {
          if tagIds.isEmpty {
            Text(.localizable(.noTagsSelected))
              .foregroundStyle(.secondary)
              .padding(.vertical, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
          } else {
            HFlow {
              ForEach(tagIds, id: \.self) { tagId in
                Button {
                  withAnimation(animation) {
                    tagIds.removeAll { $0 == tagId }
                  }
                } label: {
                  TagView(tag: store.tags[tagId]) {
                    Image(systemName: "xmark")
                      .font(.caption2)
                      .fontWeight(.bold)
                  }
                  .fixedSize()
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: tagId, in: tagNamespace)
              }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
          }
        }

        if !availableTags.isEmpty {
          CustomSection {
            VStack(spacing: 0) {
              ForEach(Array(availableTags.enumerated()), id: \.element.id) { index, tag in
                Button {
                  withAnimation(animation) {
                    tagIds.append(tag.id)
                  }
                } label: {
                  HStack {
                    TagView(tag: tag)
                      .fixedSize()
                      .matchedGeometryEffect(id: tag.id, in: tagNamespace)
                    Spacer()
                    Image(systemName: "plus")
                      .foregroundStyle(.secondary)
                  }
                  .padding(.vertical, 8)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < availableTags.count - 1 {
                  Divider()
                }
              }
            }
          }
        }
      }
      .customSectionBackgroundStyle(sheetDetent == .large ? .solid : .translucent)
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
      .navigationDestination(isPresented: $showCreateTag) {
        CreateTagView(onCreated: { tag in
          withAnimation(animation) {
            tagIds.append(tag.id)
          }
        })
        .onDisappear {
          showCreateTag = false
        }
      }
    }
    .adaptiveSheetPresentation()
    .interactiveDismissDisabled(interactiveDismissDisabled)
    .onAppear {
      tagIds = viewModel.document.tags
    }
  }
}
