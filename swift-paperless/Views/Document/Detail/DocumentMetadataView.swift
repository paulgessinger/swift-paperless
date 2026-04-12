//
//  DocumentMetadataView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

import DataModel
import Networking
import SwiftUI
import os

struct DocumentMetadataView: View {
  @Binding var document: Document
  @Binding var metadata: Metadata?

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss

  private var loaded: Bool {
    metadata != nil
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent(.documentMetadata(.modifiedDate)) {
            if let modified = document.modified {
              Text(modified, style: .date)
            } else {
              Text(.localizable(.none))
            }
          }

          LabeledContent(.documentMetadata(.addedDate)) {
            if let added = document.added {
              Text(added, style: .date)
            } else {
              Text(.localizable(.none))
            }
          }
        }

        if let metadata {
          Section {
            LabeledContent(.documentMetadata(.mediaFilename)) {
              Text(metadata.mediaFilename)
                .textSelection(.enabled)
            }

            LabeledContent(.documentMetadata(.originalFilename)) {
              Text(metadata.originalFilename)
                .textSelection(.enabled)
            }

            LabeledContent(.documentMetadata(.originalChecksum)) {
              Text(metadata.originalChecksum)
                .italic()
                .textSelection(.enabled)
            }

            LabeledContent(.documentMetadata(.originalFilesize)) {
              Text(metadata.originalSize.formatted(.byteCount(style: .file)))
            }

            LabeledContent(.documentMetadata(.originalMimeType)) {
              Text(metadata.originalMimeType)
                .textSelection(.enabled)
            }
          }

          if metadata.archiveChecksum != nil || metadata.archiveSize != nil {
            Section {
              if let archiveChecksum = metadata.archiveChecksum {
                LabeledContent(.documentMetadata(.archiveChecksum)) {
                  Text(archiveChecksum)
                    .italic()
                    .textSelection(.enabled)
                }
              }

              if let archiveSize = metadata.archiveSize {
                LabeledContent(.documentMetadata(.archiveFilesize)) {
                  Text(archiveSize.formatted(.byteCount(style: .file)))
                }
              }
            }
          }
        } else {
          Section {
            ProgressView()
              .frame(maxWidth: .infinity)
          }
        }
      }
      .animation(.spring, value: loaded)

      .navigationBarTitleDisplayMode(.inline)
      .navigationTitle(.documentMetadata(.metadata))

      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }
      }
    }

    .errorOverlay(errorController: errorController, offset: 20)
  }
}

// - MARK: Preview

#Preview {
  @Previewable @StateObject var store = DocumentStore(
    repository: PreviewRepository(downloadDelay: 3.0))
  @Previewable @StateObject var errorController = ErrorController()

  @Previewable @State var document: Document?
  @Previewable @State var metadata: Metadata?

  NavigationStack {
    VStack {
      if document != nil {
        DocumentMetadataView(document: Binding($document)!, metadata: $metadata)
      }
    }
    .task {
      try? await store.fetchAll()
      document = try? await store.document(id: 1)
      if let document {
        metadata = try? await store.repository.metadata(documentId: document.id)
      }
    }
  }
  .environmentObject(store)
  .environmentObject(errorController)
}
