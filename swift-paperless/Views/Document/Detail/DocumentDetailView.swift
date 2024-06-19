//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.06.2024.
//

import SwiftUI

struct DocumentDetailViewVersionSelection: View {
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var show = false

    var body: some View {
        VStack {
            if show {
                Picker("Document editing UI variant",
                       selection: $appSettings.editingUserInterface)
                {
                    ForEach(AppSettings.EditingUserInterface.allCases, id: \.self) { element in
                        Text("\(element)")
                            .tag(element)
                    }
                }
            }
        }
        .task {
            show = Bundle.main.appConfiguration != .AppStore
        }
    }
}

@MainActor
private var editingInterface: AppSettings.EditingUserInterface {
    switch AppSettings.shared.editingUserInterface {
    case .automatic: .v1
    case .v1: .v1
    case .v2: .v2
    }
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
        case .v2:
            DocumentDetailViewV2(store: store,
                                 document: document,
                                 navPath: navPath)
        default:
            Text("Invalid editing UI version (this is an internal error)")
        }
    }
}
