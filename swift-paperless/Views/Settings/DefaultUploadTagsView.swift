//
//  DefaultUploadTagsView.swift
//  swift-paperless
//

import AppShared
import AppViews
import SwiftUI

/// Picks the tags that are preselected when uploading a document to one server.
struct DefaultUploadTagsView: View {
  let serverID: UUID

  @Environment(ConnectionManager.self) private var connectionManager

  private var tags: Binding<[UInt]> {
    Binding(
      get: { connectionManager.connections[serverID]?.defaultUploadTags ?? [] },
      set: { connectionManager.setDefaultUploadTags($0, for: serverID) })
  }

  var body: some View {
    TagSelectionView(tags: tags)
      .navigationTitle(Text(.settings(.defaultUploadTags)))
      .navigationBarTitleDisplayMode(.inline)
  }
}
