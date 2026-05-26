//
//  DocumentTypeEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.04.23.
//

import DataModel
import SwiftUI
import os

public struct DocumentTypeEditView<Element>: View where Element: DocumentTypeProtocol {
  @State private var element: Element
  public var onSave: ((Element) throws -> Void)?

  private var saveLabel: String

  public init(element: Element, onSave: ((Element) throws -> Void)?) {
    _element = State(initialValue: element)
    self.onSave = onSave
    saveLabel = String(localized: .app(.save))
  }

  private var editable: Bool {
    onSave != nil
  }

  private func valid() -> Bool {
    !element.name.isEmpty && editable
  }

  public var body: some View {
    Form {
      Section {
        TextField(String(localized: .app(.name)), text: $element.name)
          .clearable($element.name)
          .disabled(!editable)
      }

      MatchEditView(element: $element)
        .disabled(!editable)
    }
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        SaveButton(saveLabel) {
          do {
            try onSave?(element)
          } catch {
            Logger.shared.error("Save document type error: \(error)")
          }
        }
        .disabled(!valid())
      }
    }

  }
}

extension DocumentTypeEditView where Element == ProtoDocumentType {
  public init(onSave: @escaping (Element) throws -> Void) {
    self.init(element: ProtoDocumentType(), onSave: onSave)
    saveLabel = String(localized: .app(.save))
  }
}

public struct DocumentTypeEditView_Previews: PreviewProvider {
  public struct Container: View {
    public var body: some View {
      NavigationStack {
        DocumentTypeEditView<ProtoDocumentType>(onSave: { _ in })
          .navigationBarTitleDisplayMode(.inline)
          .navigationTitle(Text(.app(.documentTypeEditTitle)))
      }
    }
  }

  public static var previews: some View {
    Container()
  }
}
