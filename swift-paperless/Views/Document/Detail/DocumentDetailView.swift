//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.06.2024.
//

import DataModel
import SwiftUI

struct DocumentDetailViewVersionSelection: View {
    @ObservedObject private var appSettings = AppSettings.shared

    let available: [AppSettings.EditingUserInterface] = [
        .automatic,
        .v1,
        .v3,
    ]

    var body: some View {
        VStack {
            Picker("Document editing UI variant",
                   selection: $appSettings.editingUserInterface)
            {
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
    case .v1: .v1
    case .v2: .automatic
    case .v3: .v3
    }
}

@MainActor
protocol DocumentDetailViewProtocol: View {
    init(store: DocumentStore,
         document: Document,
         navPath: Binding<NavigationPath>?)
}

struct DocumentDetailView: View {
    @ObservedObject private var store: DocumentStore
    @State var document: Document
    var navPath: Binding<NavigationPath>?

    init(store: DocumentStore,
         document: Document,
         navPath: Binding<NavigationPath>? = nil)
    {
        self.store = store
        self.document = document
        self.navPath = navPath
    }

    var body: some View {
        switch editingInterface {
        case .v1:
            DocumentDetailViewV1(store: store,
                                 document: document,
                                 navPath: navPath)
        case .v3:
            DocumentDetailViewV3(store: store,
                                 document: document,
                                 navPath: navPath)
        default:
            Text("Invalid editing UI version (this is an internal error)")
        }
    }
}
