//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import SwiftUI

struct MainView: View {
    @AppStorage("app_url") private var appUrl: String?

    @State private var showLoginScreen = false

    @StateObject private var store = DocumentStore(repository: NullRepository())

    @StateObject private var manager = ConnectionManager()

//    DocumentStore(repository: ApiRepository(apiHost: getCredentials(key: "API_HOST"), apiToken: getCredentials(key: "API_TOKEN")))

    var body: some View {
        Group {
            if manager.state == .valid {
                DocumentView()
                    .environmentObject(store)
                    .environmentObject(manager)
            }
            else {
//                Text("LOGIN PLACEHOLDER VIEW")
            }
        }
        .fullScreenCover(isPresented: $showLoginScreen) {
            LoginView(connectionManager: manager)
        }
        .task {
//            manager.logout()
            await manager.check()
        }
        .onChange(of: manager.state) { value in
            showLoginScreen = value == .invalid
        }
        .onChange(of: manager.connection) { _ in
            if let conn = manager.connection {
//                print("Set conn")
                store.set(repository: ApiRepository(connection: conn))
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
