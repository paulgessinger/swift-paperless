//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.06.2024.
//

import DataModel
import Networking
import SwiftUI

@MainActor
protocol DocumentDetailViewProtocol: View {
  init(
    store: DocumentStore,
    connection: Connection?,
    document: Document,
    navPath: Binding<[NavigationState]>?)
}

struct DocumentDetailView: View {
  @ObservedObject private var store: DocumentStore
  @EnvironmentObject private var connectionManager: ConnectionManager
  @State var document: Document
  var navPath: Binding<[NavigationState]>?

  init(
    store: DocumentStore,
    document: Document,
    navPath: Binding<[NavigationState]>? = nil
  ) {
    self.store = store
    self.document = document
    self.navPath = navPath
  }

  var body: some View {
    if AppFeatures.enabled(.documentDetailViewV4) {
      DocumentDetailViewV4(
        store: store,
        connection: connectionManager.connection,
        document: document,
        navPath: navPath
      )
    } else {
      DocumentDetailViewV3(
        store: store,
        connection: connectionManager.connection,
        document: document,
        navPath: navPath
      )
    }
  }
}
