//
//  DefaultUploadTagsView.swift
//  swift-paperless
//

import AppShared
import DataModel
import SwiftUI

/// Picks the tags that are preselected when uploading a document to one
/// server.
struct DefaultUploadTagsView: View {
  let connectionId: UUID

  // `DocumentTagEditView` edits the tags of a document, so a scratch
  // document carries the selection and every change is written through.
  @State private var document: ProtoDocument

  init(connectionId: UUID) {
    self.connectionId = connectionId
    _document = State(
      initialValue: ProtoDocument(
        tags: AppSettings.shared.defaultUploadTags(for: connectionId)))
  }

  var body: some View {
    DocumentTagEditView(document: $document)
      .navigationTitle(Text(.settings(.defaultUploadTags)))
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: document.tags) { _, tags in
        AppSettings.shared.setDefaultUploadTags(tags, for: connectionId)
      }
  }
}
