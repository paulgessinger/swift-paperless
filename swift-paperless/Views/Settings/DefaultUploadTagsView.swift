//
//  DefaultUploadTagsView.swift
//  swift-paperless
//

import AppShared
import AppViews
import SwiftUI

/// Picks the tags that are preselected when uploading a document to one server.
struct DefaultUploadTagsView: View {
  @Bindable var defaults: UploadDefaults

  var body: some View {
    TagSelectionView(tags: $defaults.tags)
      .navigationTitle(Text(.settings(.defaultUploadTags)))
      .navigationBarTitleDisplayMode(.inline)
  }
}
