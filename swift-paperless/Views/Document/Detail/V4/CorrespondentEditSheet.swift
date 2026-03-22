//
//  CorrespondentEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import DataModel
import Networking
import SwiftUI

struct CorrespondentEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @Environment(\.sheetDetent) private var sheetDetent

  @State private var searchText = ""
  @State private var saving = false

  private var correspondents: [Correspondent] {
    let search = searchText.lowercased()
    return store.correspondents.values
      .filter { search.isEmpty || $0.name.lowercased().contains(search) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private var selectedCorrespondent: Correspondent? {
    viewModel.document.correspondent.flatMap { store.correspondents[$0] }
  }

  private func select(correspondent: UInt?) {
    guard !saving else { return }
    guard viewModel.document.correspondent != correspondent else {
      dismiss()
      return
    }

    Task {
      do {
        saving = true
        var document = viewModel.document
        document.correspondent = correspondent
        async let updatedDocument = store.updateDocument(document)
        async let delay: () = Task.sleep(for: .seconds(0.3))

        let updated = try await updatedDocument
        try await delay
        viewModel.document = updated
        saving = false
        dismiss()
      } catch {
        saving = false
        errorController.push(error: error)
      }
    }
  }

  private func row(_ label: String, id: UInt?) -> some View {
    Button {
      select(correspondent: id)
    } label: {
      HStack {
        Text(label)
          .foregroundStyle(.primary)
        Spacer()
        if viewModel.document.correspondent == id {
          Label(String(localized: .localizable(.elementIsSelected)), systemImage: "checkmark")
            .labelStyle(.iconOnly)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(saving)
  }

  var body: some View {
    NavigationStack {
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          CustomSection {
            if let selectedCorrespondent {
              Button {
                select(correspondent: nil)
              } label: {
                HStack {
                  Text(selectedCorrespondent.name)
                    .foregroundStyle(.primary)
                  Spacer()
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(saving)
            } else {
              Text(.localizable(.correspondentNotAssignedPicker))
                .foregroundStyle(.secondary)
            }
          } header: {
            Text(.localizable(.selected))
          }

          CustomSection {
            VStack(spacing: 0) {
              ForEach(Array(correspondents.enumerated()), id: \.element.id) {
                index, correspondent in
                row(correspondent.name, id: correspondent.id)

                if index < correspondents.count - 1 {
                  Divider()
                }
              }
            }
          } header: {
            Text(.localizable(.correspondents))
          }
        }
      }
      .customSectionBackgroundStyle(sheetDetent == .large ? .solid : .translucent)
      .scrollBounceBehavior(.basedOnSize)
      .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
      .navigationTitle(.localizable(.correspondent))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          }
        }
      }
    }
    .adaptiveSheetPresentation()
    .interactiveDismissDisabled(saving)
  }
}
