//
//  StoragePathEditSheet.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.04.26.
//

import AppShared
import DataModel
import Networking
import SwiftUI

struct StoragePathEditSheet: View {
  @Bindable var viewModel: DocumentDetailModel

  @Environment(DocumentStore.self) private var store

  private struct CreateStoragePathView: View {
    @Environment(DocumentStore.self) private var store
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
      .navigationTitle(Text(.app(.storagePathCreateTitle)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  var body: some View {
    SingleSelectPickerSheet(
      viewModel: viewModel,
      storeKeyPath: \.storagePaths,
      keyPath: \.storagePath,
      navigationTitle: .app(.storagePath),
      listSectionTitle: .app(.storagePaths),
      notAssignedLabel: .app(.storagePathNotAssignedPicker),
      canCreate: store.permissions.test(.add, for: .storagePath),
      suggestions: viewModel.suggestions.storagePaths,
      createView: { onCreated in
        CreateStoragePathView(onCreated: onCreated)
      }
    )
  }
}
