//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Collections
import os
import SwiftUI

struct MainView: View {
    @AppStorage("app_url") private var appUrl: String?

    @State private var showLoginScreen = false

    @State private var storeReady = false
    @State private var store: DocumentStore?
    @StateObject private var filterModel = FilterModel()

    @StateObject private var manager = ConnectionManager()

    @StateObject private var errorController = ErrorController()

//    DocumentStore(repository: ApiRepository(apiHost: getCredentials(key: "API_HOST"), apiToken: getCredentials(key: "API_TOKEN")))

    var body: some View {
        Group {
            if manager.state == .valid, storeReady {
                DocumentView()
                    .errorOverlay(errorController: errorController)
                    .environmentObject(store!)
                    .environmentObject(manager)
                    .environmentObject(filterModel)
                    .environmentObject(errorController)
            } else {
                //                Text("LOGIN PLACEHOLDER VIEW")
            }

//            Text(String(describing: errorController.active))
        }
        .fullScreenCover(isPresented: $showLoginScreen) {
            LoginView(connectionManager: manager)
                .errorOverlay(errorController: errorController)
                .environmentObject(errorController)
        }

        .task {
            Logger.shared.notice("Checking login status")
            await manager.check()
        }
        .onChange(of: manager.state) { value in
            showLoginScreen = value == .invalid
        }
        .onChange(of: manager.state) { _ in
            if let conn = manager.connection {
                store = DocumentStore(repository: ApiRepository(connection: conn))
                storeReady = true
            }
        }
    }
}

@main
struct swift_paperlessApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
