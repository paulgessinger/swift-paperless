//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.06.2024.
//

import DataModel
import Networking
import SwiftUI

struct DocumentDetailViewVersionSelection: View {
  @ObservedObject private var appSettings = AppSettings.shared

  let available: [AppSettings.EditingUserInterface] = [
    .automatic,
    .v3,
  ]

  var body: some View {
    VStack {
      Picker(
        "Document editing UI variant",
        selection: $appSettings.editingUserInterface
      ) {
        ForEach(available, id: \.self) { element in
          Text("\(element.rawValue)")
            .tag(element)
        }
      }
    }
  }
}

@MainActor
private var editingInterface: AppSettings.EditingUserInterface {
  switch AppSettings.shared.editingUserInterface {
  case .automatic:
    switch Bundle.main.appConfiguration {
    case .Debug, .Simulator: .v3
    case .AppStore: .v3
    case .TestFlight: .v3
    }
  case .v3: .v3
  default: .automatic
  }
}

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
    switch editingInterface {
    case .v3:
      DocumentDetailViewV3(
        store: store,
        connection: connectionManager.connection,
        document: document,
        navPath: navPath)
    default:
      Text("Invalid editing UI version (this is an internal error)")
    }
  }
}
