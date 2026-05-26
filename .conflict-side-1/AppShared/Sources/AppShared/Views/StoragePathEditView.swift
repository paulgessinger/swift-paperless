//
//  StoragePathEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import DataModel
import SwiftUI
import os

public struct StoragePathEditView<Element>: View where Element: StoragePathProtocol {
  @State private var storagePath: Element
  public var onSave: ((Element) throws -> Void)?

  private var saveLabel: String

  public init(
    element storagePath: Element,
    onSave: ((Element) throws -> Void)?
  ) {
    _storagePath = State(initialValue: storagePath)
    self.onSave = onSave
    saveLabel = String(localized: .app(.save))
  }

  public var isValid: Bool {
    !storagePath.name.isEmpty && !storagePath.path.isEmpty
  }

  public var body: some View {
    Form {
      Section {
        TextField(String(localized: .app(.title)), text: $storagePath.name)
          .clearable($storagePath.name)

        TextField(String(localized: .app(.path)), text: $storagePath.path)
          .clearable($storagePath.path)
          .autocorrectionDisabled(true)
          .textInputAutocapitalization(.never)

      } header: {
        Text(.app(.properties))
      } footer: {
        Text(.app(.storagePathFormatExplanation))
      }

      MatchEditView(element: $storagePath)
    }

    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {

        SaveButton(saveLabel) {
          do {
            try onSave?(storagePath)
          } catch {
            Logger.shared.error("Save storage path error: \(error)")
          }
        }
        .disabled(!isValid)
        .bold()
      }
    }
  }
}

extension StoragePathEditView where Element == ProtoStoragePath {
  public init(onSave: @escaping (Element) throws -> Void) {
    self.init(element: ProtoStoragePath(), onSave: onSave)
    saveLabel = String(localized: .app(.add))
  }
}

#Preview {
  NavigationStack {
    StoragePathEditView<ProtoStoragePath>(onSave: { _ in })
      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(Text(.app(.storagePathCreateTitle)))
  }
}
