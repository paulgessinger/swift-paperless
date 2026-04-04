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

  private struct CreateCorrespondentView: View {
    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Correspondent) -> Void

    var body: some View {
      CorrespondentEditView<ProtoCorrespondent>(onSave: { value in
        Task {
          do {
            let correspondent = try await store.create(correspondent: value)
            onCreated(correspondent)
            dismiss()
          } catch {
            errorController.push(error: error)
          }
        }
      })
      .navigationTitle(Text(.localizable(.correspondentCreateTitle)))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  var body: some View {
    SingleSelectPickerSheet(
      viewModel: viewModel,
      allItems: { Array(store.correspondents.values) },
      keyPath: \.correspondent,
      navigationTitle: .localizable(.correspondent),
      listSectionTitle: .localizable(.correspondents),
      notAssignedLabel: .localizable(.correspondentNotAssignedPicker),
      canCreate: store.permissions.test(.add, for: .correspondent),
      createView: { onCreated in
        CreateCorrespondentView(onCreated: onCreated)
      }
    )
  }
}
