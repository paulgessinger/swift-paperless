//
//  StoragePathEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.04.26.
//

import DataModel
import Networking
import SwiftUI

struct StoragePathEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @EnvironmentObject private var store: DocumentStore

  private struct CreateStoragePathView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.dismiss) private var dismiss

    let onCreated: (StoragePath) -> Void

    var body: some View {
      StoragePathEditView<ProtoStoragePath>(onSave: { value in
        Task {
          do {
            let storagePath = try await store.create(storagePath: value)
            onCreated(storagePath)
            dismiss()
          } catch {
            errorController.push(error: error)
          }
        }
      })
      .navigationTitle(Text(.localizable(.storagePathCreateTitle)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  var body: some View {
    SingleSelectPickerSheet(
      viewModel: viewModel,
      allItems: { Array(store.storagePaths.values) },
      keyPath: \.storagePath,
      navigationTitle: .localizable(.storagePath),
      listSectionTitle: .localizable(.storagePaths),
      notAssignedLabel: .localizable(.storagePathNotAssignedPicker),
      canCreate: store.permissions.test(.add, for: .storagePath),
      suggestions: viewModel.suggestions.storagePaths,
      createView: { onCreated in
        CreateStoragePathView(onCreated: onCreated)
      }
    )
  }
}
