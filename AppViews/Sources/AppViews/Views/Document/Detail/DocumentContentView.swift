//
//  DocumentContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.10.2026.
//

import AppShared
import DataModel
import SwiftUI

/// A document's OCR text, as stored on the device. Opening the document keeps
/// it and the files phase fetches it for kept documents, so this reads the
/// store alone and works offline.
public struct DocumentContentView: View {
  @Binding private var document: Document

  @Environment(DocumentStore.self) private var store

  @State private var text: String?
  @State private var loaded = false

  public init(document: Binding<Document>) {
    _document = document
  }

  public var body: some View {
    NavigationStack {
      Group {
        if !loaded {
          ProgressView()
        } else if let text, !text.isEmpty {
          ScrollView {
            Text(text)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding()
          }
        } else {
          ContentUnavailableView {
            Label(.documentMetadata(.contentEmptyTitle), systemImage: "doc.plaintext")
          } description: {
            Text(.documentMetadata(.contentEmptyDescription))
          }
        }
      }
      .animation(.spring, value: loaded)

      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(.documentMetadata(.content))

      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
      }

      // The detail load replaces the text when it brings a newer document.
      .task(id: document.modified) {
        text = await store.repository.storedText(document: document)
        loaded = true
      }
    }
  }
}
