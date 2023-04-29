//
//  SettingsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import SwiftUI
import SwiftUINavigation

struct SettingsView: View {
    @EnvironmentObject var store: DocumentStore

    var body: some View {
        List {
            NavigationLink {
                ManageView<TagManager>(store: store)
                    .navigationTitle("Tags")
            } label: {
                Label("Tags", systemImage: "tag.fill")
            }
        }
        .navigationTitle("Settings")
    }
}

struct SettingsView_Previews: PreviewProvider {
    struct Container: View {
        @StateObject var store = DocumentStore(repository: PreviewRepository())

        @StateObject var errorController = ErrorController()

        var body: some View {
            NavigationStack {
                SettingsView()
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(store)
            .errorOverlay(errorController: errorController)
        }
    }

    static var previews: some View {
        Container()
    }
}
